-- MLR-006: an account whose local-currency MRR did not change must be 'retained',
-- even in January when the planning rate resets and its USD value moves.
select f.account_id, f.month_start, f.billing_currency, f.movement_type, f.fx_rebase_mrr_usd
from {{ ref('fct_mrr') }} as f
inner join {{ ref('int_account_mrr_monthly') }} as prev
    on  prev.account_id = f.account_id
    and cast({{ dbt.dateadd('month', 1, 'prev.month_start') }} as date) = f.month_start
where prev.mrr_local > 0
  and prev.mrr_local = f.mrr_local
  and f.movement_type <> 'retained'
