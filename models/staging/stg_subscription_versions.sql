-- Grain: one row per subscription version (SCD2). A new version is written on every
-- plan, seat or price change. valid_to is exclusive; open versions get a far-future sentinel.
select
    subscription_id || '-' || cast(version_number as varchar)        as subscription_version_id,
    subscription_id,
    version_number,
    account_id,
    plan_id,
    billing_interval,
    seats,
    currency,
    unit_price_local,
    discount_pct,
    mrr_local,                         -- already normalised to a monthly amount (annual ACV / 12), net of recurring discount
    valid_from                                                         as valid_from_utc,
    coalesce(valid_to, cast('9999-12-31' as timestamp))                as valid_to_utc,
    valid_to is null                                                   as is_current,
    change_reason
from {{ ref('raw_subscription_versions') }}
where valid_to is null or valid_to > valid_from   -- zero-length versions carry no MRR
