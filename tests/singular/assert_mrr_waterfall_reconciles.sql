-- MLR-005/006: for every month, closing MRR must equal
--   opening MRR + FX rebase + new + expansion + reactivation - contraction - churn.
-- If this ever fails, a movement is being lost or double counted.
with monthly as (
    select
        month_start,
        sum(mrr_usd)                 as closing_mrr,
        sum(prev_mrr_usd_reported)   as opening_mrr,
        sum(fx_rebase_mrr_usd)       as fx_rebase,
        sum(new_mrr_usd)             as new_mrr,
        sum(expansion_mrr_usd)       as expansion,
        sum(reactivation_mrr_usd)    as reactivation,
        sum(contraction_mrr_usd)     as contraction,
        sum(churned_mrr_usd)         as churned
    from {{ ref('fct_mrr') }}
    group by month_start
),

checked as (
    select
        *,
        lag(closing_mrr) over (order by month_start) as prior_month_closing
    from monthly
)

select *
from checked
where abs(closing_mrr - (opening_mrr + fx_rebase + new_mrr + expansion + reactivation - contraction - churned)) > 0.01
   or (prior_month_closing is not null and abs(opening_mrr - prior_month_closing) > 0.01)
