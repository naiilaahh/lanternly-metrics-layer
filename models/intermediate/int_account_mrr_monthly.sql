-- Grain: one row per reportable account per month, from the account's first subscription
-- month through the last closed month (rows continue after churn with mrr_local = 0).
--
-- MLR-005: MRR is a month-END snapshot: the recurring amount in force at the last instant
-- of the month (UTC), i.e. just before 00:00 UTC on the 1st of the next month. A change that
-- takes effect at exactly 00:00 on the 1st belongs to the NEW month. Several changes inside
-- one month net out, so an upgrade + downgrade in the same month is no movement at all.
-- MLR-001/002: MRR is read from contract versions, never from invoices or refunds.
with months as (
    {{ month_spine() }}
),

versions as (
    select v.*
    from {{ ref('stg_subscription_versions') }} as v
    inner join {{ ref('int_accounts_reportable') }} as a on a.account_id = v.account_id
),

first_seen as (
    select account_id, min(valid_from_utc) as first_version_at
    from versions
    group by account_id
),

account_months as (
    select
        f.account_id,
        m.month_start,
        cast({{ dbt.dateadd('month', 1, 'm.month_start') }} as timestamp) as period_end_utc   -- exclusive
    from first_seen as f
    inner join months as m
        on m.month_start >= cast({{ dbt.date_trunc('month', 'f.first_version_at') }} as date)
)

select
    am.account_id,
    am.month_start,
    am.period_end_utc,
    coalesce(sum(v.mrr_local), 0)     as mrr_local,
    coalesce(max(v.seats), 0)         as seats,
    max(v.plan_id)                    as plan_id,
    max(v.billing_interval)           as billing_interval
from account_months as am
left join versions as v
    on  v.account_id = am.account_id
    and v.valid_from_utc <  am.period_end_utc
    and v.valid_to_utc   >= am.period_end_utc
group by am.account_id, am.month_start, am.period_end_utc
