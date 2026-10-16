-- MLR-011: the event pipeline is at-least-once, so the same event_id can arrive twice.
-- Deduplicate on event_id, keep the first copy. Events with no user (system webhooks) are dropped.
with ranked as (
    select
        event_id,
        nullif(user_id, '')    as user_id,
        account_id,
        event_name,
        occurred_at_utc,
        row_number() over (partition by event_id order by occurred_at_utc) as copy_number
    from {{ ref('raw_product_events') }}
)
select event_id, user_id, account_id, event_name, occurred_at_utc
from ranked
where copy_number = 1
  and user_id is not null
