-- MLR-007: GRR can never exceed 100% or exceed NRR, for any as-of month.
with by_month as (
    select
        as_of_month,
        sum(retained_mrr_capped_usd) / sum(starting_mrr_usd) as grr,
        sum(current_mrr_usd)         / sum(starting_mrr_usd) as nrr
    from {{ ref('fct_retention_12m') }}
    group by as_of_month
)
select * from by_month where grr > 1 or grr > nrr or grr < 0
