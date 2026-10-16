-- Two rate tables on purpose (MLR-006):
--   actual monthly rates -> used for recognised revenue (what finance books)
--   fixed fiscal-year planning rates -> used for MRR/ARR so FX swings never show up as expansion or contraction
select 'actual' as rate_type, rate_month, cast(null as integer) as fiscal_year, currency, usd_per_unit
from {{ ref('raw_fx_rates_monthly') }}
union all
select 'planning' as rate_type, cast(null as date) as rate_month, fiscal_year, currency, usd_per_unit
from {{ ref('raw_fx_planning_rates') }}
