-- Grain: one row per account per month (month-end snapshot).
-- Certified source for: mrr, arr, active_customers, the MRR movement waterfall,
-- logo churn and the SaaS quick ratio.
--
-- Constant-currency rule (MLR-006): MRR is converted at the fiscal-year PLANNING rate of the
-- month being reported. Movements are measured with BOTH months at the current month's rate,
-- so an FX rate change can never be booked as expansion or contraction. When the planning
-- rate resets in January, the restatement of last month's MRR is isolated in fx_rebase_mrr_usd.
with base as (
    select
        m.account_id,
        m.month_start,
        m.mrr_local,
        m.seats,
        m.plan_id,
        m.billing_interval,
        a.billing_currency,
        r.usd_per_unit as planning_rate
    from {{ ref('int_account_mrr_monthly') }} as m
    inner join {{ ref('int_accounts_reportable') }} as a on a.account_id = m.account_id
    inner join {{ ref('int_planning_fx_rates') }} as r
        on  r.currency = a.billing_currency
        and r.fiscal_year = extract(year from m.month_start)
),

windowed as (
    select
        *,
        coalesce(lag(mrr_local) over (partition by account_id order by month_start), 0)               as prev_mrr_local,
        coalesce(lag(planning_rate) over (partition by account_id order by month_start), planning_rate) as prev_planning_rate,
        coalesce(max(case when mrr_local > 0 then 1 else 0 end) over (
            partition by account_id order by month_start
            rows between unbounded preceding and 1 preceding), 0)                                      as had_paid_before
    from base
),

classified as (
    select
        *,
        case
            when prev_mrr_local = 0 and mrr_local > 0 and had_paid_before = 0 then 'new'
            when prev_mrr_local = 0 and mrr_local > 0                          then 'reactivation'
            when prev_mrr_local > 0 and mrr_local = 0                          then 'churn'
            when prev_mrr_local > 0 and mrr_local > prev_mrr_local             then 'expansion'
            when prev_mrr_local > 0 and mrr_local < prev_mrr_local             then 'contraction'
            when prev_mrr_local > 0                                            then 'retained'
            else 'inactive'
        end as movement_type
    from windowed
)

select
    account_id || '|' || cast(month_start as varchar)                         as account_month_id,
    account_id,
    month_start,
    billing_currency,
    plan_id,
    billing_interval,
    seats,
    mrr_local,
    planning_rate,
    mrr_local * planning_rate                                                 as mrr_usd,
    mrr_local * planning_rate * 12                                            as arr_usd,
    prev_mrr_local * prev_planning_rate                                       as prev_mrr_usd_reported,
    movement_type,
    mrr_local > 0                                                             as is_active_customer,
    prev_mrr_local > 0                                                        as is_starting_customer,
    -- movement amounts: all positive numbers, at the CURRENT month's planning rate
    prev_mrr_local * (planning_rate - prev_planning_rate)                     as fx_rebase_mrr_usd,
    case when movement_type = 'new'          then mrr_local * planning_rate else 0 end                      as new_mrr_usd,
    case when movement_type = 'expansion'    then (mrr_local - prev_mrr_local) * planning_rate else 0 end   as expansion_mrr_usd,
    case when movement_type = 'contraction'  then (prev_mrr_local - mrr_local) * planning_rate else 0 end   as contraction_mrr_usd,
    case when movement_type = 'churn'        then prev_mrr_local * planning_rate else 0 end                 as churned_mrr_usd,
    case when movement_type = 'reactivation' then mrr_local * planning_rate else 0 end                      as reactivation_mrr_usd,
    case when movement_type = 'new'          then 1 else 0 end                                              as new_customer_count,
    case when movement_type = 'churn'        then 1 else 0 end                                              as churned_customer_count,
    case when movement_type = 'reactivation' then 1 else 0 end                                              as reactivated_customer_count,
    case when mrr_local > 0                  then 1 else 0 end                                              as active_customer_count,
    case when prev_mrr_local > 0             then 1 else 0 end                                              as starting_customer_count
from classified
