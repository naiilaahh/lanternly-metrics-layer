-- MLR-008 fixtures planted by the data generator:
--   usr_fixture_tokyo  event 2026-08-31 20:30 UTC = 2026-09-01 05:30 Asia/Tokyo  -> 2026-09-01
--   usr_fixture_la     event 2026-09-01 03:00 UTC = 2026-08-31 20:00 America/LA  -> 2026-08-31
with expected as (
    select 'usr_fixture_tokyo' as user_id, cast('2026-09-01' as date) as activity_date
    union all
    select 'usr_fixture_la', cast('2026-08-31' as date)
)
select e.*
from expected as e
left join {{ ref('fct_user_activity_daily') }} as a
    on a.user_id = e.user_id and a.activity_date = e.activity_date
where a.user_id is null
