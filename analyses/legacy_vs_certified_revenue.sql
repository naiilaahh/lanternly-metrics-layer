-- Impact analysis attached to the PR that deprecated total_revenue_legacy (RFC-0001 §5.3).
-- Shows why invoice-based "revenue" was retired: annual prepayments land in one month.
select
    month_start,
    round(sum(gross_billings_usd), 0)                                         as total_revenue_legacy,
    round(sum(net_revenue_usd), 0)                                            as net_revenue_certified,
    round(100.0 * (sum(gross_billings_usd) - sum(net_revenue_usd)) / nullif(sum(net_revenue_usd), 0), 1) as legacy_overstatement_pct
from {{ ref('fct_revenue_monthly') }}
group by month_start
order by month_start
