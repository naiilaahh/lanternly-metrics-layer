-- Grain: one row per month (company level). Certified source for LTV and LTV:CAC, which need
-- trailing windows that a semantic layer cannot express as a ratio of additive measures.
-- (CAC and CAC payback ARE ratios of additive measures, so they live in the semantic layer.)
--
-- MLR-013  CAC uses a trailing-3-month window (spend and new logos both summed over 3 months)
-- MLR-014  LTV = ARPA x gross margin % x expected lifetime, where lifetime = 1 / trailing-6-month
--          average monthly logo churn, capped at var('ltv_max_lifetime_months')
with mrr as (
    select
        month_start,
        sum(mrr_usd)                  as mrr_usd,
        sum(active_customer_count)    as active_customers,
        sum(starting_customer_count)  as starting_customers,
        sum(churned_customer_count)   as churned_customers,
        sum(new_customer_count)       as new_customers,
        sum(new_mrr_usd)              as new_mrr_usd
    from {{ ref('fct_mrr') }}
    group by month_start
),

revenue as (
    select month_start, sum(net_revenue_usd) as net_revenue_usd
    from {{ ref('fct_revenue_monthly') }}
    group by month_start
),

costs as (
    select
        month_start,
        sum(case when cost_type = 'cogs' then amount_usd else 0 end)        as cogs_usd,
        sum(case when cost_type = 'acquisition' then amount_usd else 0 end) as acquisition_cost_usd
    from {{ ref('fct_company_costs_monthly') }}
    group by month_start
),

monthly as (
    select
        m.month_start,
        m.mrr_usd,
        m.active_customers,
        m.starting_customers,
        m.churned_customers,
        m.new_customers,
        m.new_mrr_usd,
        r.net_revenue_usd,
        c.cogs_usd,
        c.acquisition_cost_usd
    from mrr as m
    left join revenue as r on r.month_start = m.month_start
    left join costs   as c on c.month_start = m.month_start
),

rolling as (
    select
        *,
        sum(acquisition_cost_usd) over w3 as acquisition_cost_t3m_usd,
        sum(new_customers)        over w3 as new_customers_t3m,
        sum(new_mrr_usd)          over w3 as new_mrr_t3m_usd,
        sum(net_revenue_usd)      over w3 as net_revenue_t3m_usd,
        sum(cogs_usd)             over w3 as cogs_t3m_usd,
        sum(churned_customers)    over w6 as churned_customers_t6m,
        sum(starting_customers)   over w6 as starting_customers_t6m,
        count(*)                  over w6 as months_in_window
    from monthly
    window
        w3 as (order by month_start rows between 2 preceding and current row),
        w6 as (order by month_start rows between 5 preceding and current row)
),

ratios as (
    select
        *,
        mrr_usd / nullif(active_customers, 0)                                        as arpa_usd,
        (net_revenue_t3m_usd - cogs_t3m_usd) / nullif(net_revenue_t3m_usd, 0)        as gross_margin_pct_t3m,
        churned_customers_t6m * 1.0 / nullif(starting_customers_t6m, 0)              as logo_churn_rate_t6m,
        acquisition_cost_t3m_usd / nullif(new_customers_t3m, 0)                      as cac_t3m_usd,
        new_mrr_t3m_usd / nullif(new_customers_t3m, 0)                               as new_customer_arpa_t3m_usd
    from rolling
),

final as (
    select
        month_start,
        mrr_usd,
        active_customers,
        arpa_usd,
        gross_margin_pct_t3m,
        logo_churn_rate_t6m,
        coalesce(least(1.0 / nullif(logo_churn_rate_t6m, 0), {{ var('ltv_max_lifetime_months') }}),
                 {{ var('ltv_max_lifetime_months') }})                                    as expected_lifetime_months,
        cac_t3m_usd,
        new_customer_arpa_t3m_usd,
        arpa_usd * gross_margin_pct_t3m
            * coalesce(least(1.0 / nullif(logo_churn_rate_t6m, 0), {{ var('ltv_max_lifetime_months') }}),
                       {{ var('ltv_max_lifetime_months') }})                              as ltv_usd,
        months_in_window = 6                                                               as is_window_complete
    from ratios
)

select
    *,
    ltv_usd / nullif(cac_t3m_usd, 0) as ltv_to_cac_ratio
from final
