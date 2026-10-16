select
    cost_month,
    channel,
    cost_category,
    amount_usd,
    is_acquisition_cost      -- false for retention costs such as Customer Success (MLR-012)
from {{ ref('raw_acquisition_costs') }}
