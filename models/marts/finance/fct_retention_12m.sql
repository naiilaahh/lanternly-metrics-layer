-- Grain: one row per as-of month per account that was paying exactly 12 months earlier.
-- Certified source for NRR and GRR (trailing-twelve-month, cohort method).
--
-- MLR-007: the cohort is fixed at the start of the window. Customers acquired during the
-- window are excluded; customers that churned and came back inside the window count at
-- their current MRR. GRR caps each account at its starting MRR, so expansion can never
-- offset churn. Both sides are valued at the as-of month's planning rate (MLR-006).
select
    cur.account_id || '|' || cast(cur.month_start as varchar)            as retention_row_id,
    cur.account_id,
    cur.month_start                                                       as as_of_month,
    start.month_start                                                     as cohort_month,
    start.mrr_local * cur.planning_rate                                   as starting_mrr_usd,
    cur.mrr_local   * cur.planning_rate                                   as current_mrr_usd,
    least(cur.mrr_local, start.mrr_local) * cur.planning_rate             as retained_mrr_capped_usd,
    case when cur.mrr_local > 0 then 1 else 0 end                         as is_retained_logo
from {{ ref('fct_mrr') }} as start
inner join {{ ref('fct_mrr') }} as cur
    on  cur.account_id = start.account_id
    and cur.month_start = cast({{ dbt.dateadd('month', 12, 'start.month_start') }} as date)
where start.mrr_local > 0
