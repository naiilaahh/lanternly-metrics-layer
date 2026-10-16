select
    user_id,
    account_id,
    created_at                                   as created_at_utc,
    nullif(timezone, '')                         as user_timezone,
    email_domain,
    (is_internal or email_domain = 'lanternly.io') as is_internal_user
from {{ ref('raw_users') }}
