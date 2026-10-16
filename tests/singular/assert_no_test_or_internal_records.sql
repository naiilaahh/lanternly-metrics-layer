-- MLR-010: test accounts and internal users must not reach any certified mart.
select 'fct_mrr' as model, account_id as id from {{ ref('fct_mrr') }}
where account_id in (select account_id from {{ ref('stg_accounts') }} where is_test_account)
union all
select 'fct_revenue_monthly', account_id from {{ ref('fct_revenue_monthly') }}
where account_id in (select account_id from {{ ref('stg_accounts') }} where is_test_account)
union all
select 'fct_user_activity_daily', user_id from {{ ref('fct_user_activity_daily') }}
where user_id in (select user_id from {{ ref('stg_users') }} where is_internal_user)
   or account_id in (select account_id from {{ ref('stg_accounts') }} where is_test_account)
