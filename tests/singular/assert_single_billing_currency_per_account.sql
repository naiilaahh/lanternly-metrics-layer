-- The constant-currency method (MLR-006) assumes an account bills in ONE currency.
-- A currency switch must be modelled as churn + new under RFC-0001, so fail loudly if one appears.
select account_id, count(distinct currency) as n_currencies
from {{ ref('stg_subscription_versions') }}
group by account_id
having count(distinct currency) > 1
