-- Grain: one row per local calendar day. Company-level DAU, 28-day MAU and stickiness.
--
-- MLR-015: MAU is a ROLLING 28-day window (d-27 .. d), not a calendar month, so that
-- February is comparable to March and every window holds exactly four of each weekday.
-- Days without a complete 28-day lookback are flagged and excluded from certified views.
with activity as (
    select user_id, activity_date from {{ ref('fct_user_activity_daily') }}
),

days as (
    select distinct activity_date as metric_date from activity
),

bounds as (
    select min(activity_date) as first_day from activity
)

select
    d.metric_date,
    count(distinct case when a.activity_date = d.metric_date then a.user_id end)                       as dau,
    count(distinct a.user_id)                                                                           as mau_28d,
    count(distinct case when a.activity_date = d.metric_date then a.user_id end) * 1.0
        / nullif(count(distinct a.user_id), 0)                                                          as stickiness,
    d.metric_date >= cast({{ dbt.dateadd('day', 27, 'b.first_day') }} as date)                          as is_window_complete
from days as d
cross join bounds as b
inner join activity as a
    on  a.activity_date <= d.metric_date
    and a.activity_date >  cast({{ dbt.dateadd('day', -28, 'd.metric_date') }} as date)
group by d.metric_date, b.first_day
