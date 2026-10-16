select cost_month, cost_category, amount_usd
from {{ ref('raw_cogs') }}
