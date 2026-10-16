-- MLR-004: certified marts stop at the last closed month. An open month is a partial month.
select 'fct_mrr' as model, max(month_start) as max_month from {{ ref('fct_mrr') }}
having max(month_start) <> cast('{{ var("last_closed_month") }}' as date)
union all
select 'fct_revenue_monthly', max(month_start) from {{ ref('fct_revenue_monthly') }}
having max(month_start) <> cast('{{ var("last_closed_month") }}' as date)
