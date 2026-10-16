# Lanternly Metrics Layer

**A governed metrics catalog and semantic layer for a B2B SaaS company: 33 metrics, one definition each, tested in CI and served to every BI tool from one place.**

> Lanternly is a fictional workflow-automation SaaS company. Every account, invoice and event in
> this repo is synthetic, produced by [`scripts/generate_synthetic_data.py`](scripts/generate_synthetic_data.py).
> The organisational story (dashboard sprawl, three churn numbers) is a realistic scenario
> written to frame the work.

---

## The problem

Lanternly ran 140+ dashboards across three BI tools, and each one computed its own metrics.
Before a board meeting the company had three churn numbers, ARR that moved with exchange
rates, and "revenue" that spiked in renewal months because one dashboard summed invoices.
Analysts spent about 30 hours a month reconciling numbers instead of analysing them.

## What this project delivers

| Deliverable | Where | What it shows |
|---|---|---|
| **Metrics catalog** (33 metrics, 5 domains) | [`docs/metrics_catalog.md`](docs/metrics_catalog.md) · [`metrics_catalog/metrics_catalog.xlsx`](metrics_catalog/) | Definition, formula, tier, status, version, owner, steward, SLA, lineage, consumers, review and deprecation dates |
| **Governance matrix** | `metrics_catalog.xlsx` → *Governance Matrix*, *Change Approvals* tabs | RACI by domain, plus who approves which kind of change |
| **Metric logic rules** (16 edge-case rules) | [`docs/metric_logic_rules.md`](docs/metric_logic_rules.md) | How refunds, FX, time zones, reactivations, prorations and test data are handled. Each rule maps to code and a test |
| **Semantic layer** (dbt + MetricFlow) | [`models/semantic/`](models/semantic/) | 8 semantic models, semi-additive balances, ratio/derived/cumulative metrics, conformed account dimension |
| **dbt transformation project** | [`models/`](models/) | staging → intermediate → marts, cross-database macros |
| **Metrics Governance RFC** | [`docs/rfc/RFC-0001-metrics-governance.md`](docs/rfc/RFC-0001-metrics-governance.md) | Tiers, lifecycle, RACI, versioning, 90-day deprecation, closed-period policy, success metrics |
| **Governance automation** | [`scripts/lint_metrics.py`](scripts/lint_metrics.py), [`.github/`](.github/) | CI blocks merges for missing owners, overdue reviews, short deprecation notice, certified-on-beta dependencies |

## Design decisions worth reading

1. **The YAML is the catalog.** Governance metadata (owner, tier, status, version, review date,
   logic rules, consumers) sits next to the metric logic in `_metrics.yml`. The catalog is
   generated from it, so documentation can't drift from code.
2. **Refunds never touch MRR** (MLR-001). The revenue treatment depends on the reason: a service
   credit is contra-revenue in the refund month, a duplicate charge is a cash correction only,
   and an early-termination refund returns deferred revenue that was never recognised.
3. **Constant-currency MRR with an explicit FX line** (MLR-006). Movements value both months at
   the current planning rate, so a stronger dollar never looks like contraction. When the
   planning rate resets in January, the restatement gets its own `fx_rebase` waterfall line,
   and `closing = opening + fx_rebase + new + expansion + reactivation − contraction − churn`
   holds every month. A test checks it.
4. **Semi-additive balances in the semantic layer.** MRR, customers, NRR bases and LTV use
   `non_additive_dimension`, so a quarter query returns the quarter-end balance, not three
   months added together. Ratios like CAC are built from additive parts, so quarterly CAC is
   quarter spend divided by quarter new logos.
5. **Local-time activity** (MLR-008). DAU/MAU use the user's own calendar day (user time zone,
   then account time zone, then UTC) through a dispatched macro that compiles on
   Postgres/DuckDB, Snowflake and Databricks. In the sample data, 28% of events from users in
   the Americas fall on a different date in UTC.
6. **Deprecation done properly.** `total_revenue_legacy` is still served, labelled, with a
   named replacement and a sunset date 183 days out. The impact analysis in
   [`analyses/legacy_vs_certified_revenue.sql`](analyses/legacy_vs_certified_revenue.sql)
   shows it overstating FY26 revenue by up to 92% in heavy renewal months.

## Sample output (synthetic data, September 2026 / Q3 FY26)

| Metric | Value | | Metric | Value |
|---|---|---|---|---|
| ARR | $17.8M | | Gross margin (Q3) | 78.4% |
| Active customers | 470 | | Blended CAC (Q3) | $21.9k |
| ARPA | $3,161 / month | | CAC payback (Q3) | 15.1 months |
| NRR (TTM) | 111.8% | | LTV | $104.5k |
| GRR (TTM) | 87.6% | | LTV : CAC | 4.8x |
| Logo churn (Q3, avg monthly) | 2.4% | | 28-day MAU · stickiness | 2,013 · 23.7% |

## Tests

75 tests, all passing on the reference build:

- **Reconciliation:** the MRR waterfall closes every month, the customer roll-forward closes,
  and mart MRR equals the contract roll-up.
- **Edge cases:** FX is never booked as a movement, annual prepayments never show up as revenue,
  local-date fixtures for Tokyo and Los Angeles, passive-only users are never active, CAC
  excludes Customer Success, and only closed months are reported.
- **Unit tests (dbt ≥ 1.10):** movement classification across a fiscal-year FX reset, and
  month-end boundary behaviour. The boundary test caught a real off-by-one in the first
  draft: changes effective at exactly 00:00 UTC on the 1st were landing in the previous month.
- **Generic tests:** keys, accepted values, relationships, ranges and row-level invariants
  such as `arr = mrr × 12` and `GRR ≤ min(start, current)`.

## Repository map

```
├── models/
│   ├── staging/         10 views: rename, type, dedupe, flag test/internal
│   ├── intermediate/    exclusions applied once, month-end MRR snapshot, local-time activity
│   ├── marts/finance/   dim_accounts, fct_mrr, fct_retention_12m, fct_revenue_monthly,
│   │                    fct_company_costs_monthly, fct_unit_economics_monthly (+ unit tests)
│   ├── marts/product/   fct_user_activity_daily, fct_engagement_daily
│   └── semantic/        _semantic_models.yml, _metrics.yml (source of truth), time spine
├── macros/              to_local_date (dispatched), month_spine, generate_schema_name
├── tests/singular/      12 reconciliation and edge-case tests
├── seeds/               synthetic raw data (11 tables, ~57k rows)
├── scripts/             data generator, governance linter, catalog builder
├── metrics_catalog/     generated catalog (.csv, .xlsx)
├── docs/                RFC-0001, metric logic rules, catalog, architecture
├── analyses/            legacy vs certified revenue, example semantic-layer queries
└── .github/             CI workflow, metric change request form, PR checklist, CODEOWNERS
```

## Run it

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp profiles.example.yml profiles.yml        # point at a local Postgres (or use the duckdb target)
export DBT_PROFILES_DIR=.

python scripts/generate_synthetic_data.py   # optional: seeds are committed; this regenerates them
dbt deps
dbt build                                   # seeds + models + all tests
python scripts/lint_metrics.py              # governance checks
python scripts/build_metrics_catalog.py     # regenerate the catalog
mf query --metrics arr,net_revenue_retention --group-by metric_time__quarter
```

More queries are in [`analyses/semantic_layer_queries.md`](analyses/semantic_layer_queries.md).

## Skills demonstrated

| Area | Evidence |
|---|---|
| KPI frameworks | 33 metrics in a tiered hierarchy (board → operating → component), with input/output relationships made explicit through derived metrics and lineage |
| Metrics governance | RFC with lifecycle, RACI, semver, deprecation and closed-period policy, enforced by CI lint, CODEOWNERS and templates |
| Semantic layer strategy | Logic centralised in MetricFlow, not BI tools. Semi-additive measures, conformed dimensions, cumulative windows |
| Metric logic validation | 16 documented edge-case rules, each tied to an implementation and a test. Reconciliation tests. dbt unit tests |
| Multi-tool delivery | Tool-agnostic semantic layer, cross-database macros, generated catalog for glossary tools |
| Product ownership | Problem framing, success metrics with baselines and targets, phased rollout, open questions |
