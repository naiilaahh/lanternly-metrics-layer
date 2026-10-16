select
    refund_id,
    invoice_id,
    refunded_at   as refunded_at_utc,
    currency,
    amount        as amount_local,
    reason        as refund_reason
from {{ ref('raw_refunds') }}
