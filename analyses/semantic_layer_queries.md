# Example Semantic Layer queries

The same governed definitions, queried from any tool through MetricFlow (`mf` CLI shown;
Tableau, Power BI, Hex and the embedded app use the Semantic Layer JDBC / GraphQL APIs).

```bash
# Board pack: quarter-end ARR, NRR, GRR and LTV:CAC. Semi-additive balances return the quarter-END value.
mf query --metrics arr,net_revenue_retention,gross_revenue_retention,ltv_to_cac \
         --group-by metric_time__quarter --start-time 2026-01-01

# MRR waterfall by month
mf query --metrics new_mrr,expansion_mrr,reactivation_mrr,contraction_mrr,churned_mrr,net_new_mrr \
         --group-by metric_time__month --order metric_time__month

# Churn by segment. `segment` comes from dim_accounts through the `account` entity, with no join in the BI tool.
mf query --metrics logo_churn_rate,churned_mrr --group-by metric_time__quarter,account__segment

# CAC and payback by quarter: computed as quarter spend / quarter new logos, not an average of monthly ratios
mf query --metrics cac,cac_payback_months --group-by metric_time__quarter

# Product health: daily DAU, rolling 28-day MAU, stickiness
mf query --metrics dau,mau,stickiness --group-by metric_time__day --start-time 2026-08-28

# Inspect the SQL MetricFlow generates for a metric
mf query --metrics net_revenue_retention --group-by metric_time__month --explain
```
