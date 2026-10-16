-- MLR-003: voided invoices are billing errors, not revenue. They are kept for audit with is_void.
select
    invoice_id,
    account_id,
    nullif(subscription_id, '')                         as subscription_id,
    issued_at                                           as issued_at_utc,
    currency,
    amount                                              as amount_local,
    line_type,
    line_type in ('subscription', 'subscription_proration') as is_recurring_line,
    status,
    status = 'void'                                     as is_void,
    service_period_start                                as service_period_start_utc,
    service_period_end                                  as service_period_end_utc
from {{ ref('raw_invoice_lines') }}
