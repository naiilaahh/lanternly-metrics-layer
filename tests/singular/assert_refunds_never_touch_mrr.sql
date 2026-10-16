-- MLR-001: MRR is computed from contract versions only. This guards against anyone
-- "fixing" a dashboard by joining refunds into the MRR model: total MRR must equal the
-- contract-version roll-up exactly.
with from_contracts as (
    select month_start, sum(mrr_local) as mrr_local
    from {{ ref('int_account_mrr_monthly') }}
    group by month_start
),
from_mart as (
    select month_start, sum(mrr_local) as mrr_local
    from {{ ref('fct_mrr') }}
    group by month_start
)
select c.month_start, c.mrr_local as contracts, m.mrr_local as mart
from from_contracts as c
full outer join from_mart as m on m.month_start = c.month_start
where coalesce(c.mrr_local, -1) <> coalesce(m.mrr_local, -1)
