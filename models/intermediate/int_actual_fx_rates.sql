-- Actual monthly average rates used for recognised revenue, COGS-side reporting and refunds.
select rate_month, currency, usd_per_unit
from {{ ref('stg_fx_rates') }}
where rate_type = 'actual'
