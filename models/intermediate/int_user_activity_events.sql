-- Qualifying activity events, localised to the user's own calendar day.
--   MLR-008  local date uses user tz -> account tz -> UTC (in that order)
--   MLR-009  passive events (digest opens, heartbeats, login page views) are not activity
--   MLR-010  internal employees and test accounts are excluded
select
    e.event_id,
    e.user_id,
    e.account_id,
    e.event_name,
    e.occurred_at_utc,
    coalesce(u.user_timezone, a.account_timezone, 'UTC')                                   as resolved_timezone,
    {{ to_local_date('e.occurred_at_utc', "coalesce(u.user_timezone, a.account_timezone, 'UTC')") }} as activity_date
from {{ ref('stg_product_events') }} as e
inner join {{ ref('stg_users') }} as u on u.user_id = e.user_id
inner join {{ ref('int_accounts_reportable') }} as a on a.account_id = e.account_id
where not u.is_internal_user
  and e.event_name not in (
      {%- for name in var('passive_event_names') %}'{{ name }}'{% if not loop.last %}, {% endif %}{% endfor -%}
  )
