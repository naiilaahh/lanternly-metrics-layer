-- Grain: one row per user per LOCAL calendar day with at least one qualifying event.
-- Certified source for active_users and the 28-day MAU (MLR-008, MLR-009, MLR-010, MLR-011).
select
    user_id || '|' || cast(activity_date as varchar) as user_day_id,
    user_id,
    account_id,
    activity_date,
    max(resolved_timezone)                            as resolved_timezone,
    count(*)                                          as qualifying_event_count
from {{ ref('int_user_activity_events') }}
group by user_id, account_id, activity_date
