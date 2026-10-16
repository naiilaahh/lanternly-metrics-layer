-- Customers at month end = customers at start + new + reactivated - churned.
with monthly as (
    select
        month_start,
        sum(active_customer_count)      as closing,
        sum(starting_customer_count)    as opening,
        sum(new_customer_count)         as new_logos,
        sum(reactivated_customer_count) as reactivated,
        sum(churned_customer_count)     as churned
    from {{ ref('fct_mrr') }}
    group by month_start
)
select *
from monthly
where closing <> opening + new_logos + reactivated - churned
