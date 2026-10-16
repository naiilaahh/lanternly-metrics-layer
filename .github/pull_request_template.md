## What changed

<!-- Metric(s) touched and a one-line summary. Link the metric change request issue. -->
Closes #

## Change classification (RFC-0001 §5.2)

- [ ] MAJOR: historical values change (parallel `_v2` metric + 30-day notice + one-close dual-run)
- [ ] MINOR: new dimension / filter / grain, history unchanged
- [ ] PATCH: docs only
- [ ] New metric (starts as `beta`)
- [ ] Deprecation (`sunset_on` ≥ 90 days out, `replaced_by` set)

## Review checklist

- [ ] Definition states inclusions, exclusions and time-grain behaviour
- [ ] Every edge case maps to a logic rule (MLR-xxx) with a test
- [ ] Unit / reconciliation tests added or updated, and `dbt build` passes
- [ ] `python scripts/lint_metrics.py` passes
- [ ] Catalog regenerated (`python scripts/build_metrics_catalog.py`)
- [ ] Impact analysis attached: old vs new for the last 6 closed months
- [ ] `consumers` updated and affected dashboard owners tagged

## Impact analysis

| Month | Old value | New value | Δ | Explanation |
|---|---|---|---|---|
