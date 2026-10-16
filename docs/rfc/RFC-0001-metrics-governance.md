# RFC-0001: Metrics Governance and the Certified Metrics Layer

| | |
|---|---|
| **Status** | Accepted (v1.2) |
| **Author** | Analytics Product Owner, Data Platform |
| **Reviewers** | VP Finance (FP&A), CRO (RevOps), VP Customer Success, Head of Product Analytics, Analytics Engineering lead |
| **Decision forum** | Metrics Council, 2026-02-18 |
| **Supersedes** | "KPI definitions" Confluence page (2023), per-dashboard calculated fields |

## 1. Problem

Lanternly reports the same business through 140+ dashboards in three BI tools. Each one
computes its own metrics. In the Q4 FY25 board prep we found:

- **Three churn numbers** for the same month: CS counted cancellation requests, Finance
  counted contracts ending, and the product team counted logins stopping.
- **ARR that moved with exchange rates.** EUR and GBP contracts were converted at spot, so a
  stronger dollar showed up as "contraction".
- **Revenue that spiked in renewal months**, because one dashboard summed invoices (annual
  prepayments included) and another used recognised revenue.
- **About 30 analyst hours per month** spent reconciling numbers before leadership meetings.

The cause is structural. Business logic lives in BI calculated fields, where it can't be
versioned, reviewed, tested or reused.

## 2. Goals and non-goals

**Goals**

1. Each business metric has **one** definition and **one** accountable owner, published in a catalog anyone can read.
2. Metric logic lives in **one** layer (dbt + MetricFlow semantic layer). Every tool reads from it: Tableau, Power BI, notebooks, the embedded customer app.
3. Changes to metric logic are **proposed, reviewed, versioned and tested** like code.
4. Consumers get **advance notice** of changes and deprecations, and closed periods are never silently restated.

**Non-goals**

- Governing every ad-hoc analysis. Exploratory work can stay in notebooks until it becomes a recurring metric.
- Picking a BI tool. The semantic layer is tool-agnostic on purpose.
- Data quality of upstream source systems. That is covered by the source-freshness and contract checks in RFC-0003.

## 3. Proposal overview

```
 proposal (GitHub issue)  ->  PR to models/semantic/_metrics.yml  ->  CI (lint + dbt build + tests)
          |                                |                                   |
     triage <= 5 days              owner + steward review                 merge = release
          |                        (+ Metrics Council for tier 1)        catalog regenerated
```

Every metric is a YAML definition with a `governance` block (tier, status, owner, steward,
version, review date, logic rules, consumers). That YAML is the source of truth. The
published catalog (`docs/metrics_catalog.md`, `metrics_catalog/*.xlsx`) is **generated** from
it and never edited by hand.

## 4. Tiers, lifecycle and roles

**Tiers** decide how much rigour a metric needs.

| Tier | Meaning | Examples | Change approval | Review cycle |
|---|---|---|---|---|
| 1 · Board | Reported to the board or investors | ARR, NRR, GRR, CAC, LTV:CAC | Metrics Council + business owner + data steward | 12 months |
| 2 · Operating | Runs a department week to week | Expansion MRR, DAU, ARPA | Business owner + data steward | 12 months |
| 3 · Component | Building blocks and exploratory metrics | COGS, acquisition spend, quick ratio (beta) | Data steward | On change |

**Lifecycle**

```
proposed ──► beta ──► certified ──► deprecated ──► retired
              ▲            │
              └────────────┘  (failed review or overdue recertification)
```

- **Proposed**: issue opened, not built.
- **Beta**: built and queryable, labelled "beta" in every tool, no SLA. A beta metric can never be tier 1.
- **Certified**: owner sign-off, tests in place, SLA applies. Certification lapses if `next_review` passes. CI blocks merges until the metric is recertified or downgraded.
- **Deprecated**: still served, flagged in every tool, with a named `replaced_by` and a `sunset_on` date at least **90 days** away.
- **Retired**: removed from the semantic layer. Historical values stay in the warehouse archive.

**Roles (RACI)**

| Role | Who | Responsibility |
|---|---|---|
| Business owner (**A**) | A named executive role per domain (e.g. VP Finance for MRR) | Owns the business meaning. Approves changes. Answers "is this number right?" |
| Data steward (**R**) | Analytics Engineering pod for the domain | Implements logic, tests and docs. Runs the review. On call for data incidents. |
| Metrics Council (**C**) | CFO delegate, RevOps, CS, Product Analytics, AE lead. Meets every 2 weeks. | Approves tier-1 changes and disputes between domains. Owns this RFC. |
| Consumers (**I**) | Dashboard owners, analysts, embedded-app team | Get release notes and deprecation notices. Listed per metric in `consumers`. |

## 5. Change process

**5.1 Proposing.** Anyone opens a *Metric change request* issue
(`.github/ISSUE_TEMPLATE/metric_change_request.yml`). It asks for the business question, the
proposed definition, edge cases, the expected impact on history, consumers, and the decision
the metric will drive. Triage within **5 business days**: accept, merge with an existing
metric, or decline with a reason.

**5.2 Versioning.** Metrics use semantic versioning.

| Bump | When | Example | Consumer notice |
|---|---|---|---|
| MAJOR | Historical values change | Excluding Customer Success from CAC | 30 days, plus a dual-run for one month-end close |
| MINOR | New dimension, filter or grain; history unchanged | Slice NRR by region | Release notes |
| PATCH | Wording or docs only | Clarify that ARR excludes usage | None |

A MAJOR change ships behind a parallel metric (`cac_v2`) for one close. Finance reconciles
old against new. Then the old version is deprecated under §4.

**5.3 Review checklist** (enforced in the PR template):

1. The definition states inclusions, exclusions and the time-grain behaviour.
2. Each edge case maps to a logic rule (MLR-xxx) with a test.
3. Unit tests cover the classification logic. Reconciliation tests still pass.
4. Impact analysis: the old value against the new value for the last 6 closed months, attached to the PR.
5. `consumers` is updated and affected dashboard owners are tagged.

**5.4 Closed periods.** A month locks on business day 5 after month end. Late corrections go
into the period in which they happen. Restating a locked month needs a Metrics Council
decision, a MAJOR bump and a note in the board pack (MLR-004).

**5.5 Disputes.** If two domains need different definitions, both can exist only with
different names and labels (e.g. `logo_churn_rate` vs a future `seat_churn_rate`). Two
metrics never share a name. The Council decides within one meeting cycle.

## 6. Enforcement (automation over policy)

| Control | Mechanism |
|---|---|
| Required metadata, valid tier and status, review dates, 90-day deprecation notice, no certified metric built on a beta one, cited logic rules exist | `scripts/lint_metrics.py` in CI. The PR fails. |
| Logic correctness | dbt unit tests, reconciliation tests (waterfall, customer counts) and edge-case tests on every PR |
| Who can approve | `CODEOWNERS`: finance-domain YAML needs `@lanternly/finance-analytics`, and tier-1 changes need `@lanternly/metrics-council` |
| Catalog freshness | CI regenerates the catalog and fails if the committed copy differs |
| BI drift | Certified dashboards may only use semantic-layer metrics. A monthly scan flags calculated fields that recreate a certified metric. |

## 7. Measuring success

| Outcome | Metric | Baseline (Q4 FY25) | Target (Q4 FY26) |
|---|---|---|---|
| One version of the truth | Tier-1 metrics with more than one live definition | 7 | 0 |
| Adoption | Share of executive-dashboard tiles served by the semantic layer | 0% | 90% |
| Trust | Data-incident tickets about "wrong numbers" per month | 22 | ≤ 5 |
| Efficiency | Analyst hours spent reconciling before board prep | ~30 / month | ≤ 5 / month |
| Throughput | Median days from proposal to certified | n/a | ≤ 15 business days |

## 8. Alternatives considered

1. **Definitions in BI tools only (LookML or Tableau data sources).** Strong inside one tool,
   but Power BI, notebooks and the embedded app would each re-implement the logic. Rejected:
   it moves the sprawl rather than removing it.
2. **A catalog tool on its own (Atlan or Alation glossary).** Good for discovery, but a
   glossary entry doesn't compute anything, so definitions and code drift apart. Kept as a
   *consumer*: the generated catalog syncs into the glossary.
3. **A governed SQL views schema with no semantic layer.** Simpler, but views cannot handle
   semi-additive balances, ratios at arbitrary grain or cumulative windows without a separate
   view for every grain. Rejected for tier-1 metrics.

## 9. Rollout

| Phase | Scope | Exit criterion |
|---|---|---|
| 1 (done) | 12 finance metrics certified. Board pack reads from the semantic layer. | Q1 FY26 board pack has zero manual reconciliations |
| 2 (done) | Retention, unit economics, product engagement. `total_revenue_legacy` deprecated. | 31 metrics certified |
| 3 | BI drift scan. Glossary sync. Channel-level CAC (METRIC-140). | 90% of executive tiles on the semantic layer |
| 4 | The embedded customer-usage app reads `dau` / `mau` through the Semantic Layer API | One definition shared internally and with customers |

## 10. Open questions

1. Should `quick_ratio` be certified, or stay a finance-only beta metric?
2. Seat-based churn alongside logo churn: one metric with a dimension, or two metrics?
3. Retention policy for retired metric history (proposal: 7 years, matching finance records).
