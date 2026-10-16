# Metric Logic Rules (MLR)

Edge-case rules that sit underneath the certified metrics. Each rule has an ID that metric
definitions cite (`logic_rules:` in `models/semantic/_metrics.yml`), one place in the code
where it is implemented, and at least one test that fails if someone breaks it.

`scripts/lint_metrics.py` rejects any metric that cites a rule ID not defined in this file.

| ID | Rule | Implemented in | Tested by |
|---|---|---|---|
| MLR-001 | Refunds never change MRR; revenue treatment depends on refund reason | `fct_revenue_monthly`, `int_account_mrr_monthly` | `assert_refunds_never_touch_mrr` |
| MLR-002 | Revenue is recognised ratably; annual prepayments and prorations are not revenue when billed | `fct_revenue_monthly` | `assert_recurring_revenue_within_contract` |
| MLR-003 | Voided invoices are ignored | `stg_invoice_lines`, `fct_revenue_monthly` | `accepted_values(status)` |
| MLR-004 | Only closed months are reported; closed months are never silently restated | `month_spine` macro, `var('last_closed_month')` | `assert_only_closed_months_reported` |
| MLR-005 | MRR is a month-end snapshot; intra-month changes net out | `int_account_mrr_monthly` | unit test `month_end_snapshot_nets_intra_month_changes`, `assert_mrr_waterfall_reconciles` |
| MLR-006 | Constant currency for MRR; actual rates for revenue; FX never counts as expansion or contraction | `fct_mrr`, `fct_retention_12m`, `fct_revenue_monthly` | unit test `mrr_movement_classification`, `assert_fx_never_booked_as_movement`, `assert_single_billing_currency_per_account` |
| MLR-007 | Retention uses a fixed starting cohort; GRR is capped per account | `fct_retention_12m` | `assert_retention_bounds` |
| MLR-008 | Activity dates use the user's local time zone (user → account → UTC) | `to_local_date` macro, `int_user_activity_events` | `assert_activity_date_is_user_local` |
| MLR-009 | Passive events are not activity | `int_user_activity_events`, `var('passive_event_names')` | `assert_passive_events_never_count` |
| MLR-010 | Test accounts and internal users are excluded once, centrally | `int_accounts_reportable`, `int_user_activity_events` | `assert_no_test_or_internal_records` |
| MLR-011 | Product events are deduplicated on `event_id` | `stg_product_events` | `unique(event_id)` |
| MLR-012 | CAC includes acquisition spend only; retention costs are excluded | `fct_company_costs_monthly` | `assert_cac_excludes_retention_costs` |
| MLR-013 | Board ratios built on noisy monthly inputs use trailing windows | `fct_unit_economics_monthly` | `accepted_range(expected_lifetime_months)` |
| MLR-014 | LTV lifetime is capped at 60 months | `fct_unit_economics_monthly`, `var('ltv_max_lifetime_months')` | `accepted_range(expected_lifetime_months)` |
| MLR-015 | MAU is a rolling 28-day window, not a calendar month | `fct_engagement_daily`, `mau` cumulative metric | `expression_is_true(dau <= mau_28d)` |
| MLR-016 | A customer is an account with MRR > 0; free-to-paid is New, win-back is Reactivation | `fct_mrr` | unit test `mrr_movement_classification`, `assert_customer_count_reconciles` |

---

### MLR-001: Refunds never change MRR

**Rule.** MRR and ARR are read only from contract versions. A refund changes revenue or cash,
depending on why it was issued:

| Refund reason | MRR / ARR | Net revenue | Net billings (cash) |
|---|---|---|---|
| `service_credit` (outage credit, goodwill) | no change | reduced **in the refund month** | reduced |
| `duplicate_charge` (customer charged twice) | no change | no change (the duplicate was never revenue) | reduced |
| `early_termination` (unused prepaid months returned) | churn recorded **on the termination date** | no change (unearned revenue was never recognised) | reduced |

**Why.** Before the semantic layer, Sales Ops subtracted every refund from "revenue" and
Finance subtracted none, so the same month had two different revenue numbers depending on whose dashboard you opened. Refunds are also
paid weeks after the event; tying churn to the refund date put churn in the wrong month.

**Example.** An Enterprise customer on a $9,000/month annual contract terminates on 14 May and
gets $63,000 back on 17 May. May shows $9,000 of churned MRR. Net revenue for May falls only
because recognition stops on 14 May; the $63,000 refund is a cash event.

### MLR-002: Revenue is recognised ratably

**Rule.** Recurring revenue is spread day by day across each contract version. A 12-month
prepayment invoiced in March produces about 1/12 of its value in each month of the term.
`subscription_proration` invoice lines (mid-term seat true-ups) are billings for service that
is already being recognised ratably, so they are not added again. Onboarding services and usage
overage are recognised when invoiced.

**Why.** The deprecated `total_revenue_legacy` summed invoices. In FY26 sample data it differs
from recognised revenue by 40% in an average month and by up to 92% in a heavy renewal month.

### MLR-003: Voided invoices are ignored

A voided invoice is a billing error that has been re-issued. It is kept in staging for audit
(`is_void`) and excluded from every revenue and billings measure.

### MLR-004: Closed-period integrity

**Rule.** Certified marts stop at `var('last_closed_month')`. A month locks on business day 5
after month end. Late corrections (a refund booked in October against an August invoice) land
in the month they happen and **do not restate** a closed month. A restatement needs a
Metrics Council decision and a major version bump on the metric (RFC-0001 §5).

**Why.** Board decks quote last month's numbers. If those numbers change quietly, nobody
trusts any of them.

### MLR-005: Month-end snapshot

**Rule.** MRR for a month is the recurring amount in force at the last instant of that month
(UTC). A change effective at exactly 00:00 UTC on the 1st belongs to the new month. Several
changes in one month net out, so an upgrade on the 5th reversed on the 20th is no movement.
Movement classification compares two consecutive month-end snapshots.

**Why.** Counting movements event by event booked a same-month flip-flop as both expansion and
contraction, which inflated both lines in the legacy waterfall.

**Found by a test.** The first draft of the snapshot join used `valid_from <= period_end`.
That put changes effective at exactly 00:00 on the 1st into the earlier month. The unit test
`month_end_snapshot_nets_intra_month_changes` caught it before it shipped.

### MLR-006: Currency

**Rule.**

1. MRR, ARR and all movements are converted at the **fiscal-year planning rate** (constant currency).
2. Movements are measured with both months valued at the **current** month's rate, so a rate
   change is never classified as expansion or contraction.
3. When the planning rate resets in January, last month's MRR is restated at the new rate. The
   difference is reported as its own waterfall line, `fx_rebase_mrr_usd`, so
   `closing = opening + fx_rebase + new + expansion + reactivation - contraction - churn`
   holds every month.
4. Net revenue, COGS and refunds use **actual monthly** rates, which is what finance books.
5. An account bills in one currency. A currency change is modelled as churn plus new business.

**Example.** A €1,000/month customer with no contract change is worth $1,080 in December
(FY25 rate 1.08) and $1,100 in January (FY26 rate 1.10). January shows `retained` and
`fx_rebase_mrr_usd = 20`, not $20 of expansion.

### MLR-007: Retention cohorts

**Rule.** NRR and GRR for an as-of month M use the accounts with MRR > 0 in month M-12.
Their MRR in month M is compared with their MRR in month M-12, both at month M's planning rate.
Accounts acquired after M-12 are excluded. Accounts that churned and returned inside the window
count at their current MRR. GRR caps each account at its starting MRR. Logo churn rate uses
customers paying at the end of the previous month as its denominator. At quarter grain it is a
customer-weighted average monthly rate, and it is never annualised by multiplying by 12.

### MLR-008: Local time zone for activity

**Rule.** Events land in UTC. The activity date is the user's local date: user profile time
zone first, then the account's time zone, then UTC. Implemented in the dispatched
`to_local_date` macro, so Postgres, DuckDB, Snowflake and Databricks compile the right function.

**Why.** In the sample data, 28% of events from users in the Americas fall on a different
calendar day in UTC than in local time. UTC dates move evening work to "tomorrow" and create
fake weekday patterns for APAC customers.

### MLR-009: Qualifying activity

**Rule.** A user is active when they do something: run or create a workflow, view a report,
configure an integration, comment. Passive or system events do not count: `email_digest_opened`,
`session_heartbeat`, `login_page_viewed`, `api_webhook_received`. The list lives in
`var('passive_event_names')` and changes only through a metric change request.

### MLR-010: Central exclusions

**Rule.** Test and QA accounts (flagged, or named like "QA Test") are removed once, in
`int_accounts_reportable`. Every mart joins through that model, so no dashboard has to remember
the filter. Internal employees (`@lanternly.io`) are removed from activity metrics.

### MLR-011: Event deduplication

The event pipeline delivers at least once. Duplicate `event_id`s are collapsed to the first
copy in staging. Events without a `user_id` (system webhooks) are dropped there too.

### MLR-012: CAC cost basis

**Rule.** CAC includes media, sales and marketing people costs, partner commissions, sales
tooling and brand spend: everything with `is_acquisition_cost = true`. Customer Success sits in
the same GL roll-up but is a retention cost and is excluded.

**Why.** Including Customer Success raises CAC by about 10% (FY26 sample data). It also puts
Marketing and CS on opposite sides of the same budget argument.

### MLR-013: Trailing windows for board ratios

LTV:CAC uses trailing-3-month CAC and trailing-3-month gross margin. LTV uses trailing-6-month
average logo churn. Months without a complete window are flagged `is_window_complete = false`
and kept out of certified views. CAC and CAC payback are ratios of additive measures, so the
semantic layer computes them at any grain (quarter CAC = quarter spend / quarter new logos).

### MLR-014: LTV lifetime cap

Expected lifetime = 1 / monthly logo churn, capped at `var('ltv_max_lifetime_months')` (60).
Without the cap, a quarter with near-zero churn produces an LTV in the millions.

### MLR-015: Rolling 28-day MAU

MAU counts distinct active users over the 28 local days ending on the date. Every window holds
exactly four of each weekday, so February compares fairly with March. A month query returns the
value on the month's last day (`period_agg: last`). Stickiness = average DAU over the period
divided by MAU at period end.

### MLR-016: Customer definitions

An account is a customer when its month-end MRR is above zero. Free-plan accounts are never
customers. A free-to-paid conversion is **New** in the month it converts, not the month the
account signed up. An account that paid before, churned and pays again is **Reactivation**.
It is not counted as New, so win-backs do not flatter CAC.
