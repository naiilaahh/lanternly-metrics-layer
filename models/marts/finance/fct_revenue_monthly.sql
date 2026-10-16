-- Grain: one row per account per month. Certified source for net_revenue and gross margin.
--
-- Revenue is RECOGNISED, not billed (MLR-002):
--   * recurring revenue is spread day-by-day over the contract versions, so a $120k annual
--     invoice becomes ~$10k of revenue in each month of the term, never $120k in month one
--   * proration invoices are billings for recurring service already recognised ratably -> not revenue
--   * onboarding services and usage overage are recognised in the month they are invoiced
--   * voided invoices are ignored (MLR-003)
-- Refunds by reason (MLR-001):
--   * service_credit     -> contra-revenue in the refund month; closed months are never restated
--   * duplicate_charge   -> cash correction only; the duplicate was never revenue
--   * early_termination  -> returns deferred (unearned) revenue; recognition already stopped at termination
-- Converted at ACTUAL monthly FX rates (MLR-006), unlike MRR.
with skeleton as (
    select account_id, month_start, billing_currency
    from {{ ref('fct_mrr') }}
),

days_in_month as (
    select
        month_start,
        cast({{ dbt.dateadd('month', 1, 'month_start') }} as timestamp) as next_month_start,
        {{ dbt.datediff('month_start', dbt.dateadd('month', 1, 'month_start'), 'day') }} as n_days
    from (select distinct month_start from skeleton) as m
),

recurring as (
    select
        v.account_id,
        d.month_start,
        sum(
            v.mrr_local
            * {{ dbt.datediff(
                    'greatest(v.valid_from_utc, cast(d.month_start as timestamp))',
                    'least(v.valid_to_utc, d.next_month_start)',
                    'second') }}
            / (d.n_days * 86400.0)
        ) as recognized_recurring_local
    from {{ ref('stg_subscription_versions') }} as v
    inner join days_in_month as d
        on  v.valid_from_utc < d.next_month_start
        and v.valid_to_utc   > cast(d.month_start as timestamp)
    group by v.account_id, d.month_start
),

invoices as (
    select
        account_id,
        cast({{ dbt.date_trunc('month', 'issued_at_utc') }} as date)                                        as month_start,
        sum(case when line_type in ('onboarding_services', 'usage_overage') then amount_local else 0 end) as non_recurring_local,
        sum(amount_local)                                                                                  as gross_billings_local
    from {{ ref('stg_invoice_lines') }}
    where not is_void
    group by 1, 2
),

refunds as (
    select
        i.account_id,
        cast({{ dbt.date_trunc('month', 'r.refunded_at_utc') }} as date)                              as month_start,
        sum(case when r.refund_reason = 'service_credit' then r.amount_local else 0 end)             as service_credits_local,
        sum(r.amount_local)                                                                           as refunds_total_local
    from {{ ref('stg_refunds') }} as r
    inner join {{ ref('stg_invoice_lines') }} as i on i.invoice_id = r.invoice_id
    group by 1, 2
),

combined as (
    select
        s.account_id,
        s.month_start,
        s.billing_currency,
        coalesce(rc.recognized_recurring_local, 0) as recognized_recurring_local,
        coalesce(inv.non_recurring_local, 0)       as non_recurring_local,
        coalesce(rf.service_credits_local, 0)      as service_credits_local,
        coalesce(inv.gross_billings_local, 0)      as gross_billings_local,
        coalesce(rf.refunds_total_local, 0)        as refunds_total_local
    from skeleton as s
    left join recurring as rc on rc.account_id = s.account_id and rc.month_start = s.month_start
    left join invoices  as inv on inv.account_id = s.account_id and inv.month_start = s.month_start
    left join refunds   as rf on rf.account_id = s.account_id and rf.month_start = s.month_start
)

select
    c.account_id || '|' || cast(c.month_start as varchar)                                   as account_month_id,
    c.account_id,
    c.month_start,
    c.billing_currency,
    fx.usd_per_unit                                                                         as actual_rate,
    c.recognized_recurring_local * fx.usd_per_unit                                         as recognized_recurring_revenue_usd,
    c.non_recurring_local        * fx.usd_per_unit                                         as non_recurring_revenue_usd,
    c.service_credits_local      * fx.usd_per_unit                                         as service_credits_usd,
    (c.recognized_recurring_local + c.non_recurring_local - c.service_credits_local)
                                 * fx.usd_per_unit                                         as net_revenue_usd,
    c.gross_billings_local       * fx.usd_per_unit                                         as gross_billings_usd,
    c.refunds_total_local        * fx.usd_per_unit                                         as refunds_total_usd,
    (c.gross_billings_local - c.refunds_total_local) * fx.usd_per_unit                     as net_billings_usd
from combined as c
inner join {{ ref('int_actual_fx_rates') }} as fx
    on fx.currency = c.billing_currency and fx.rate_month = c.month_start
