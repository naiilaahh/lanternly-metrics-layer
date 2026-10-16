-- Grain: one row per month x cost type x channel x category.
-- MLR-012: CAC includes only costs flagged is_acquisition_cost (media, sales & marketing people,
-- partner commissions, tooling, brand). Customer Success is a retention cost and is excluded.
select
    'acquisition|' || cast(cost_month as varchar) || '|' || channel || '|' || cost_category as cost_line_id,
    cost_month                                                    as month_start,
    case when is_acquisition_cost then 'acquisition' else 'retention' end as cost_type,
    channel,
    cost_category,
    amount_usd
from {{ ref('stg_acquisition_costs') }}

union all

select
    'cogs|' || cast(cost_month as varchar) || '|' || cost_category,
    cost_month,
    'cogs',
    cast(null as varchar),
    cost_category,
    amount_usd
from {{ ref('stg_cogs') }}
