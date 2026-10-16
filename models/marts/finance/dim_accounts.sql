-- Grain: one row per reportable (non-test) account. Conformed dimension for every semantic model.
with mrr as (
    select
        account_id,
        min(case when mrr_local > 0 then month_start end) as first_paid_month,
        max(case when mrr_local > 0 then month_start end) as last_paid_month
    from {{ ref('int_account_mrr_monthly') }}
    group by account_id
)

select
    a.account_id,
    a.account_name,
    a.created_at_utc,
    cast({{ dbt.date_trunc('month', 'a.created_at_utc') }} as date)          as signup_month,
    a.segment,
    a.region,
    a.account_timezone,
    a.billing_currency,
    a.acquisition_channel,
    m.first_paid_month,
    m.last_paid_month,
    case
        when m.first_paid_month is null then 'free'
        when m.last_paid_month = cast('{{ var("last_closed_month") }}' as date) then 'paying'
        else 'churned'
    end                                                                       as customer_status
from {{ ref('int_accounts_reportable') }} as a
left join mrr as m on m.account_id = a.account_id
