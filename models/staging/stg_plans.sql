select
    plan_id,
    plan_name,
    tier_rank,
    tier_rank > 0 as is_paid_plan
from {{ ref('raw_plans') }}
