-- Fixed fiscal-year planning rates, one row per fiscal year x currency (MLR-006).
select fiscal_year, currency, usd_per_unit
from {{ ref('stg_fx_rates') }}
where rate_type = 'planning'
