"""
Governance linter for the metrics layer (RFC-0001 §6). Runs in CI on every pull request.

Fails the build when a metric definition breaks a governance rule, for example:
  * a required governance field is missing or has an invalid value
  * a certified metric has no review date, or its review is overdue
  * a deprecated metric has no sunset date or points to a replacement that doesn't exist
  * a tier-1 metric depends on a beta or deprecated metric
  * a metric cites a logic rule (MLR-xxx) that is not defined in docs/metric_logic_rules.md
  * a metric references a measure or input metric that does not exist

Usage: python scripts/lint_metrics.py [--today YYYY-MM-DD]
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import date, timedelta
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ["tier", "status", "version", "domain", "business_owner", "data_steward",
            "refresh", "logic_rules", "formula", "consumers"]
STATUSES = {"proposed", "beta", "certified", "deprecated", "retired"}
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")


def load():
    sem = yaml.safe_load(open(ROOT / "models/semantic/_semantic_models.yml"))
    met = yaml.safe_load(open(ROOT / "models/semantic/_metrics.yml"))
    measures = {m["name"] for sm in sem["semantic_models"] for m in sm.get("measures", [])}
    rules = set(re.findall(r"^### (MLR-\d{3})", open(ROOT / "docs/metric_logic_rules.md").read(), re.M))
    return met["metrics"], measures, rules


def inputs(m) -> tuple[set[str], set[str]]:
    """(measures, metrics) a metric depends on directly."""
    tp = m.get("type_params", {})
    if m["type"] in ("simple", "cumulative"):
        return {tp["measure"]}, set()
    if m["type"] == "ratio":                      # MetricFlow ratios take METRICS, not measures
        return set(), {tp["numerator"], tp["denominator"]}
    if m["type"] == "derived":
        return set(), {x["name"] for x in tp["metrics"]}
    return set(), set()


def lint(today: date) -> list[str]:
    metrics, measures, rules = load()
    by_name = {m["name"]: m for m in metrics}
    errors: list[str] = []

    for m in metrics:
        n = m["name"]
        g = (m.get("config", {}).get("meta", {}) or {}).get("governance")
        if not g:
            errors.append(f"{n}: missing config.meta.governance block")
            continue
        for f in REQUIRED:
            if g.get(f) in (None, "", []) and not (f == "logic_rules" and g.get("status") == "deprecated"):
                errors.append(f"{n}: governance.{f} is required")
        if g.get("tier") not in (1, 2, 3):
            errors.append(f"{n}: tier must be 1, 2 or 3")
        if g.get("status") not in STATUSES:
            errors.append(f"{n}: status must be one of {sorted(STATUSES)}")
        if not SEMVER.match(str(g.get("version", ""))):
            errors.append(f"{n}: version must be semver (MAJOR.MINOR.PATCH)")
        if not m.get("description") or len(m["description"].split()) < 6:
            errors.append(f"{n}: description must explain the business meaning (6+ words)")

        status = g.get("status")
        if status == "certified":
            if not g.get("certified_on") or not g.get("next_review"):
                errors.append(f"{n}: certified metrics need certified_on and next_review")
            else:
                cert, review = date.fromisoformat(g["certified_on"]), date.fromisoformat(g["next_review"])
                if review > cert + timedelta(days=366):
                    errors.append(f"{n}: next_review must be within 12 months of certification")
                if review < today:
                    errors.append(f"{n}: review overdue since {review}; recertify or downgrade to beta")
        if status == "beta" and g.get("tier") == 1:
            errors.append(f"{n}: a beta metric cannot be tier 1")
        if status == "deprecated":
            for f in ("deprecated_on", "sunset_on", "replaced_by"):
                if not g.get(f):
                    errors.append(f"{n}: deprecated metrics need {f}")
            rep = g.get("replaced_by")
            if rep and rep not in by_name:
                errors.append(f"{n}: replaced_by '{rep}' is not a defined metric")
            if g.get("deprecated_on") and g.get("sunset_on"):
                notice = (date.fromisoformat(g["sunset_on"]) - date.fromisoformat(g["deprecated_on"])).days
                if notice < 90:
                    errors.append(f"{n}: deprecation notice is {notice} days; policy minimum is 90")

        for r in g.get("logic_rules") or []:
            if r not in rules:
                errors.append(f"{n}: cites undefined logic rule {r}")

        ms, mx = inputs(m)
        for x in ms - measures:
            errors.append(f"{n}: references unknown measure '{x}'")
        for x in mx:
            if x not in by_name:
                errors.append(f"{n}: references unknown metric '{x}'")
                continue
            dep = by_name[x]["config"]["meta"]["governance"]
            if g.get("status") == "certified" and dep.get("status") in ("beta", "deprecated", "proposed"):
                errors.append(f"{n}: certified metric depends on {dep['status']} metric '{x}'")

    return errors


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--today", default=date.today().isoformat())
    args = ap.parse_args()
    errs = lint(date.fromisoformat(args.today))
    metrics, _, _ = load()
    if errs:
        print(f"Metric governance lint FAILED ({len(errs)} issue(s)):")
        for e in errs:
            print(f"  - {e}")
        sys.exit(1)
    print(f"Metric governance lint passed: {len(metrics)} metrics checked.")
