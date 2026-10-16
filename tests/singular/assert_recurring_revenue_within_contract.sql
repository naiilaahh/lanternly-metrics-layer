-- MLR-002: recognised recurring revenue in a month can never exceed the highest MRR in force
-- during that month. An annual invoice of 12x MRR must therefore never show up as revenue.
with peak as (
    select
        v.account_id,
        cast({{ dbt.date_trunc('month', 'd.month_start') }} as date) as month_start,
        max(v.mrr_local) as peak_mrr_local
    from {{ ref('stg_subscription_versions') }} as v
    inner join (select distinct month_start from {{ ref('fct_revenue_monthly') }}) as d
        on  v.valid_from_utc < cast({{ dbt.dateadd('month', 1, 'd.month_start') }} as timestamp)
        and v.valid_to_utc   > cast(d.month_start as timestamp)
    group by 1, 2
)
select r.account_id, r.month_start, r.recognized_recurring_revenue_usd, p.peak_mrr_local, r.actual_rate
from {{ ref('fct_revenue_monthly') }} as r
left join peak as p on p.account_id = r.account_id and p.month_start = r.month_start
where r.recognized_recurring_revenue_usd > coalesce(p.peak_mrr_local, 0) * r.actual_rate + 0.01
