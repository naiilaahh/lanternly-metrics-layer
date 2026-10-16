-- MLR-009: users whose only events are passive (digest opens, heartbeats) are not active.
select a.user_id
from {{ ref('fct_user_activity_daily') }} as a
where not exists (
    select 1
    from {{ ref('stg_product_events') }} as e
    where e.user_id = a.user_id
      and e.event_name not in (
          {%- for name in var('passive_event_names') %}'{{ name }}'{% if not loop.last %}, {% endif %}{% endfor -%}
      )
)
