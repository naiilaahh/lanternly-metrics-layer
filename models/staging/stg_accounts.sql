-- Grain: one row per account. MLR-010: test accounts are flagged here and excluded once, in the intermediate layer.
select
    account_id,
    account_name,
    created_at                                   as created_at_utc,
    segment,
    region,
    timezone                                     as account_timezone,
    billing_currency,
    acquisition_channel,
    sales_owner_id,
    (is_test_account or lower(account_name) like '%qa test%') as is_test_account
from {{ ref('raw_accounts') }}
