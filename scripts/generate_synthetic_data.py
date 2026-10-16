"""
Generate synthetic raw data for Lanternly, a fictional B2B SaaS company.

Every row is invented. The generator deliberately plants the edge cases the
metric logic rules (docs/metric_logic_rules.md) are written to handle:

  * annual contracts billed up front (MRR must not spike in the invoice month)
  * mid-month upgrades/downgrades, including same-month flip-flops that net to zero
  * free-plan accounts that convert to paid months after sign-up
  * churn followed by reactivation under a new subscription id
  * early-terminated annual contracts with prorated refunds
  * service-credit refunds, duplicate-charge refunds and voided invoices
  * multi-currency pricing (USD / EUR / GBP) with moving FX rates
  * test accounts and internal (employee) users that must be excluded
  * product events in UTC from users in many time zones, duplicate event ids
    (at-least-once delivery), passive events and events with no user

Usage:  python scripts/generate_synthetic_data.py   (writes CSVs into seeds/)
Deterministic: the same seed always produces the same files.
"""
from __future__ import annotations

import csv
import math
import random
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

SEED = 42
FIRST_MONTH = date(2025, 1, 1)
LAST_CLOSED_MONTH = date(2026, 9, 1)          # data extract is "as of" 2026-09-30
EXTRACT_END = datetime(2026, 10, 1, tzinfo=timezone.utc)
EVENTS_START = date(2026, 8, 1)               # product telemetry window (local dates)
EVENTS_END = date(2026, 9, 30)
OUT = Path(__file__).resolve().parents[1] / "seeds"

rng = random.Random(SEED)
UTC = timezone.utc


# --------------------------------------------------------------------------- helpers
def add_months(d: date, n: int) -> date:
    y, m = divmod(d.month - 1 + n, 12)
    return date(d.year + y, m + 1, 1)


def month_index(d: date) -> int:
    return (d.year - FIRST_MONTH.year) * 12 + d.month - FIRST_MONTH.month


def rand_ts_in_month(month: date, min_day: int = 1) -> datetime:
    nxt = add_months(month, 1)
    days = (nxt - month).days
    day = rng.randint(min_day, days)
    return datetime(month.year, month.month, day, rng.randint(0, 23), rng.randint(0, 59), tzinfo=UTC)


def iso(ts: datetime | None) -> str:
    return "" if ts is None else ts.astimezone(UTC).strftime("%Y-%m-%d %H:%M:%S")


def same_day_next_month(ts: datetime, n: int) -> datetime:
    m = add_months(date(ts.year, ts.month, 1), n)
    last = (add_months(m, 1) - timedelta(days=1)).day
    return ts.replace(year=m.year, month=m.month, day=min(ts.day, last))


def write(name: str, header: list[str], rows: list[list]) -> None:
    OUT.mkdir(exist_ok=True)
    with open(OUT / f"{name}.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  {name:<28} {len(rows):>7,} rows")


MONTHS = [add_months(FIRST_MONTH, i) for i in range(month_index(LAST_CLOSED_MONTH) + 1)]

# --------------------------------------------------------------------------- reference data
PLANS = [
    # plan_id, name, tier, USD, EUR, GBP (per seat per month, monthly billing)
    ("pln_free", "Free", 0, 0, 0, 0),
    ("pln_starter", "Starter", 1, 29, 27, 23),
    ("pln_growth", "Growth", 2, 59, 55, 47),
    ("pln_enterprise", "Enterprise", 3, 99, 92, 79),
]
PRICE = {p[0]: {"USD": p[3], "EUR": p[4], "GBP": p[5]} for p in PLANS}
TIER_PLAN = {1: "pln_starter", 2: "pln_growth", 3: "pln_enterprise"}
ANNUAL_PREPAY_DISCOUNT = 0.15

REGIONS = {
    "NA": (0.55, ["America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles"]),
    "EMEA": (0.30, ["Europe/London", "Europe/Berlin", "Europe/Paris", "Europe/Amsterdam"]),
    "APAC": (0.15, ["Asia/Tokyo", "Australia/Sydney", "Asia/Singapore", "Asia/Kolkata"]),
}
SEGMENTS = {
    #           weight, seats range, base tier, p_annual, monthly churn, p_expand, p_contract
    "SMB": (0.62, (3, 15), 1, 0.25, 0.032, 0.040, 0.015),
    "Mid-Market": (0.29, (15, 80), 2, 0.55, 0.016, 0.055, 0.015),
    "Enterprise": (0.09, (80, 400), 3, 0.85, 0.007, 0.060, 0.010),
}
CHANNELS = {
    "SMB": [("paid_search", 0.45), ("organic", 0.35), ("partner", 0.20)],
    "Mid-Market": [("outbound", 0.50), ("paid_search", 0.20), ("partner", 0.20), ("organic", 0.10)],
    "Enterprise": [("outbound", 0.80), ("partner", 0.20)],
}
SEG_CAC = {"SMB": 5_500, "Mid-Market": 34_000, "Enterprise": 130_000}

ADJ = ["Apex", "Blue", "Cedar", "Delta", "Ember", "Falcon", "Granite", "Harbor", "Iron", "Juniper",
       "Keystone", "Lumen", "Maple", "North", "Onyx", "Pine", "Quartz", "River", "Summit", "Tidal",
       "Union", "Vantage", "Willow", "Yarrow", "Zephyr", "Copper", "Silver", "Atlas", "Beacon", "Crest"]
NOUN = ["Logistics", "Health", "Labs", "Foods", "Capital", "Robotics", "Media", "Energy", "Freight",
        "Analytics", "Dental", "Studios", "Retail", "Systems", "Legal", "Partners", "Biotech", "Motors",
        "Insurance", "Hospitality", "Builders", "Outfitters", "Networks", "Learning", "Clinics"]
SUFFIX = ["Inc", "Co", "Group", "LLC", "GmbH", "Ltd", "Corp", "Holdings"]


def pick(weighted):
    r, acc = rng.random(), 0.0
    for item, w in weighted:
        acc += w
        if r <= acc:
            return item
    return weighted[-1][0]


# --------------------------------------------------------------------------- simulation
accounts, versions, invoices, refunds = [], [], [], []
counters = {"sub": 0, "inv": 0, "ref": 0}
# planning-rate MRR by month (USD), used to scale COGS
PLAN_RATE = {"USD": 1.0, "EUR": 1.08, "GBP": 1.27}
mrr_by_month = {m: 0.0 for m in MONTHS}
new_paying_by_month_channel: dict[tuple, float] = {}


def next_id(kind: str, prefix: str) -> str:
    counters[kind] += 1
    return f"{prefix}_{counters[kind]:06d}"


def unit_price(plan_id: str, currency: str, interval: str) -> float:
    p = PRICE[plan_id][currency]
    return round(p * (1 - ANNUAL_PREPAY_DISCOUNT), 2) if interval == "year" else p


def new_invoice(acct, sub_id, issued: datetime, amount: float, currency: str, line_type: str,
                period_start: datetime | None, period_end: datetime | None, status: str = "paid"):
    if issued >= EXTRACT_END or amount == 0:
        return None
    inv_id = next_id("inv", "inv")
    if status == "paid" and issued >= datetime(2026, 9, 1, tzinfo=UTC) and rng.random() < 0.06:
        status = "open"
    invoices.append([inv_id, acct, sub_id, iso(issued), currency, round(amount, 2), line_type, status,
                     iso(period_start), iso(period_end)])
    return inv_id


def new_refund(inv_id, refunded_at: datetime, amount: float, currency: str, reason: str):
    if inv_id is None or refunded_at >= EXTRACT_END or amount <= 0:
        return
    refunds.append([next_id("ref", "ref"), inv_id, iso(refunded_at), currency, round(amount, 2), reason])


class Sub:
    def __init__(self, acct, plan_id, seats, interval, currency, discount, start: datetime, reason):
        self.id = next_id("sub", "sub")
        self.acct, self.plan, self.seats, self.interval = acct, plan_id, seats, interval
        self.currency, self.discount, self.start = currency, discount, start
        self.version_no = 0
        self.history: list[tuple[datetime, datetime | None, float]] = []   # (from, to, mrr_local)
        self.open_version(start, reason)

    @property
    def mrr(self) -> float:
        return round(self.seats * unit_price(self.plan, self.currency, self.interval) * (1 - self.discount), 2)

    def open_version(self, ts: datetime, reason: str):
        self.version_no += 1
        self.cur = [self.id, self.version_no, self.acct, self.plan, self.interval, self.seats, self.currency,
                    unit_price(self.plan, self.currency, self.interval), self.discount, self.mrr, ts, None, reason]
        versions.append(self.cur)
        self.history.append((ts, None, self.mrr))

    def close_version(self, ts: datetime):
        self.cur[11] = ts
        f, _, m = self.history[-1]
        self.history[-1] = (f, ts, m)

    def change(self, ts: datetime, reason: str, seats=None, plan=None):
        old_mrr = self.mrr
        self.close_version(ts)
        if seats is not None:
            self.seats = max(1, seats)
        if plan is not None:
            self.plan = plan
        self.open_version(ts, reason)
        return old_mrr

    def mrr_at(self, ts: datetime) -> float:
        for f, t, m in self.history:
            if f <= ts and (t is None or ts < t):
                return m
        return 0.0


def bill_subscription(sub: Sub, end: datetime | None, segment: str):
    """Issue invoices for the life of a subscription. Annual = 12x MRR up front at each renewal."""
    if sub.plan == "pln_free" and len(sub.history) == 1:
        return
    step = 12 if sub.interval == "year" else 1
    k = 0
    while True:
        d = same_day_next_month(sub.start, k)
        if (end is not None and d >= end) or d >= EXTRACT_END:
            break
        m = sub.mrr_at(d)
        if m > 0:
            period_end = same_day_next_month(sub.start, k + step)
            inv = new_invoice(sub.acct, sub.id, d, m * step, sub.currency, "subscription", d, period_end)
            r = rng.random()
            if inv and r < 0.015:                                       # service credit
                new_refund(inv, d + timedelta(days=rng.randint(5, 40)), m * rng.uniform(0.1, 0.5),   # credit of up to half a month
                           sub.currency, "service_credit")
            elif inv and r < 0.020:                                     # duplicate charge, refunded in full
                dup = new_invoice(sub.acct, sub.id, d + timedelta(minutes=3), m * step, sub.currency,
                                  "subscription", d, period_end)
                new_refund(dup, d + timedelta(days=rng.randint(1, 6)), m * step, sub.currency, "duplicate_charge")
            elif inv and r < 0.030:                                     # billing error: void + re-issue
                invoices[-1][7] = "void"
                new_invoice(sub.acct, sub.id, d + timedelta(days=1), m * step, sub.currency, "subscription",
                            d, period_end)
        k += step


def simulate_account(i: int, month: date):
    seg = pick([(s, v[0]) for s, v in SEGMENTS.items()])
    _, (lo, hi), base_tier, p_annual, p_churn, p_exp, p_con = SEGMENTS[seg]
    region = pick([(r, v[0]) for r, v in REGIONS.items()])
    tz = rng.choice(REGIONS[region][1])
    currency = "GBP" if tz == "Europe/London" else ("EUR" if region == "EMEA" else "USD")
    channel = pick(CHANNELS[seg])
    created = rand_ts_in_month(month)
    acct = f"acc_{i:05d}"
    is_test = rng.random() < 0.02
    name = (f"Lanternly QA Test {i}" if is_test and rng.random() < 0.5
            else f"{rng.choice(ADJ)} {rng.choice(NOUN)} {rng.choice(SUFFIX)}")
    accounts.append([acct, name, iso(created), seg, region, tz, currency, channel,
                     "true" if is_test else "false", f"rep_{rng.randint(1, 24):02d}"])

    seats = rng.randint(lo, hi)
    interval = "year" if rng.random() < p_annual else "month"
    discount = rng.choice([0, 0, 0, 0.1, 0.2]) if seg != "SMB" else rng.choice([0, 0, 0, 0, 0.1])
    free_start = seg == "SMB" and rng.random() < 0.10
    plan = "pln_free" if free_start else TIER_PLAN[base_tier]
    if free_start:
        interval, discount = "month", 0
    sub = Sub(acct, plan, seats, interval, currency, discount, created, "free_signup" if free_start else "new")
    if seg == "Enterprise":
        inv = new_invoice(acct, sub.id, created, rng.choice([5000, 7500, 10000, 15000]),
                          currency, "onboarding_services", None, None)
    paying_since = None if free_start else month
    active, churned_at_month, all_subs = True, None, []
    m0 = month_index(month)

    def record_new(mth):
        key = (mth, channel)
        new_paying_by_month_channel[key] = new_paying_by_month_channel.get(key, 0) + SEG_CAC[seg] * rng.uniform(0.7, 1.3)

    if paying_since:
        record_new(month)

    for mi in range(m0 + 1, len(MONTHS)):
        mth = MONTHS[mi]
        if active:
            months_in = mi - month_index(date(sub.start.year, sub.start.month, 1))
            if sub.plan == "pln_free":
                if rng.random() < 0.05:                                 # free -> paid conversion
                    ts = rand_ts_in_month(mth)
                    sub.close_version(ts)
                    all_subs.append((sub, ts))
                    sub = Sub(acct, "pln_starter", seats, "month", currency, 0, ts, "free_to_paid")
                    record_new(mth)
                continue
            renewal = sub.interval == "month" or months_in % 12 == 0
            p = p_churn if sub.interval == "month" else (1 - (1 - p_churn) ** 12) * 0.9
            if renewal and rng.random() < p:
                ts = rand_ts_in_month(mth) if sub.interval == "month" else same_day_next_month(sub.start, months_in)
                sub.close_version(ts)
                all_subs.append((sub, ts))
                active, churned_at_month = False, mi
                continue
            if sub.interval == "year" and not renewal and rng.random() < 0.003:    # early termination
                ts = rand_ts_in_month(mth)
                sub.close_version(ts)
                all_subs.append((sub, ts))
                active, churned_at_month = False, mi
                sub.early_term = ts
                continue
            r = rng.random()
            if r < p_exp:
                ts = rand_ts_in_month(mth)
                if sub.plan != "pln_enterprise" and rng.random() < 0.25:
                    old = sub.change(ts, "plan_upgrade", plan=TIER_PLAN[min(3, PLANS[[p[0] for p in PLANS].index(sub.plan)][2] + 1)])
                else:
                    old = sub.change(ts, "seat_expansion", seats=math.ceil(sub.seats * rng.uniform(1.1, 1.5)))
                if sub.interval == "year":                                # prorated true-up, billed now
                    months_left = 12 - (months_in % 12)
                    new_invoice(acct, sub.id, ts, (sub.mrr - old) * months_left, currency,
                                "subscription_proration", ts, None)
            elif r < p_exp + p_con and renewal:
                ts = rand_ts_in_month(mth) if sub.interval == "month" else same_day_next_month(sub.start, months_in)
                sub.change(ts, "seat_contraction", seats=math.floor(sub.seats * rng.uniform(0.7, 0.9)))
            elif r < p_exp + p_con + 0.004 and sub.interval == "month":   # same-month flip-flop (nets to zero)
                d1 = datetime(mth.year, mth.month, 5, 10, tzinfo=UTC)
                d2 = datetime(mth.year, mth.month, 20, 10, tzinfo=UTC)
                s0 = sub.seats
                sub.change(d1, "seat_expansion", seats=s0 + 5)
                sub.change(d2, "seat_contraction", seats=s0)
            if seg in ("Mid-Market", "Enterprise") and rng.random() < 0.10:
                new_invoice(acct, sub.id, rand_ts_in_month(mth), rng.randint(200, 2000), currency,
                            "usage_overage", None, None)
        elif not is_test and 1 <= mi - churned_at_month <= 8 and rng.random() < 0.05:   # reactivation
            ts = rand_ts_in_month(mth)
            sub = Sub(acct, TIER_PLAN[base_tier], max(1, int(seats * rng.uniform(0.6, 1.1))), "month",
                      currency, 0, ts, "reactivation")
            active = True

    if active:
        all_subs.append((sub, None))
    for s, end in all_subs:
        bill_subscription(s, end, seg)
        et = getattr(s, "early_term", None)
        if et:                                                            # prorated refund of unused term
            last_inv = [r for r in invoices if r[2] == s.id and r[6] == "subscription" and r[7] == "paid"]
            if last_inv:
                months_in = month_index(date(et.year, et.month, 1)) - month_index(date(s.start.year, s.start.month, 1))
                unused = 12 - (months_in % 12) - 1
                new_refund(last_inv[-1][0], et + timedelta(days=3), s.history[-1][2] * max(unused, 0),
                           currency, "early_termination")
        if not is_test:
            for mth in MONTHS:
                cutoff = datetime(*add_months(mth, 1).timetuple()[:3], tzinfo=UTC)
                mrr_by_month[mth] += s.mrr_at(cutoff) * PLAN_RATE[currency]
    return acct, seg, tz, created, all_subs, is_test


print("Simulating accounts ...")
acct_meta = []
n = 0
for idx, mth in enumerate(MONTHS):
    for _ in range(int(20 + idx * 0.9 + rng.randint(-4, 4))):
        n += 1
        acct_meta.append(simulate_account(n, mth))

# --------------------------------------------------------------------------- FX + costs
fx_rows, planning_rows = [], []
eur, gbp = 1.08, 1.27
for mth in MONTHS:
    eur = round(eur * rng.uniform(0.985, 1.015), 4)
    gbp = round(gbp * rng.uniform(0.985, 1.015), 4)
    fx_rows += [[mth.isoformat(), "USD", 1.0], [mth.isoformat(), "EUR", eur], [mth.isoformat(), "GBP", gbp]]
planning_rows = [[2025, "USD", 1.0], [2025, "EUR", 1.08], [2025, "GBP", 1.27],
                 [2026, "USD", 1.0], [2026, "EUR", 1.10], [2026, "GBP", 1.29]]

acq_rows = []
for mth in MONTHS:
    for ch in ["paid_search", "organic", "partner", "outbound"]:
        attributable = new_paying_by_month_channel.get((mth, ch), 0)
        if ch == "paid_search":
            acq_rows.append([mth.isoformat(), ch, "media", round(attributable * 0.75, 2), "true"])
            acq_rows.append([mth.isoformat(), ch, "people", round(attributable * 0.25, 2), "true"])
        elif ch == "organic":
            acq_rows.append([mth.isoformat(), ch, "content_and_seo", round(attributable, 2), "true"])
        elif ch == "partner":
            acq_rows.append([mth.isoformat(), ch, "partner_commissions", round(attributable, 2), "true"])
        else:
            acq_rows.append([mth.isoformat(), ch, "people", round(attributable * 0.85, 2), "true"])
            acq_rows.append([mth.isoformat(), ch, "tooling", round(attributable * 0.15, 2), "true"])
    acq_rows.append([mth.isoformat(), "brand", "events_and_sponsorships", round(rng.uniform(20_000, 45_000), 2), "true"])
    # Customer Success is a retention cost: it lives in the same GL bucket but must NOT enter CAC (MLR-012)
    acq_rows.append([mth.isoformat(), "customer_success", "people", round(rng.uniform(60_000, 90_000), 2), "false"])

cogs_rows = []
for mth in MONTHS:
    base = mrr_by_month[mth]
    cogs_rows += [[mth.isoformat(), "cloud_hosting", round(base * rng.uniform(0.10, 0.13), 2)],
                  [mth.isoformat(), "customer_support", round(base * rng.uniform(0.06, 0.08), 2)],
                  [mth.isoformat(), "third_party_apis", round(base * rng.uniform(0.02, 0.035), 2)]]

# --------------------------------------------------------------------------- users + product events
print("Simulating product usage ...")
users, events = [], []
uid = 0
QUALIFYING = ["workflow_run", "workflow_run", "workflow_run", "workflow_created", "report_viewed",
              "integration_configured", "comment_added"]
PASSIVE = ["email_digest_opened", "session_heartbeat", "login_page_viewed"]
ev_counter = 0


def emit(user_id, acct, name, ts_utc: datetime):
    global ev_counter
    ev_counter += 1
    eid = f"evt_{ev_counter:08d}"
    events.append([eid, user_id, acct, name, iso(ts_utc)])
    if rng.random() < 0.01:                                      # at-least-once delivery duplicate
        events.append([eid, user_id, acct, name, iso(ts_utc)])


days = [EVENTS_START + timedelta(days=d) for d in range((EVENTS_END - EVENTS_START).days + 1)]
for acct, seg, tz, created, subs, is_test in acct_meta:
    max_seats = max(v[5] for v in versions if v[2] == acct)
    n_users = max(1, min(15, math.ceil(max_seats * 0.12)))
    region_tzs = next(v[1] for v in REGIONS.values() if tz in v[1])
    acct_users = []
    for _ in range(n_users):
        uid += 1
        r = rng.random()
        utz = tz if r < 0.7 else (rng.choice(region_tzs) if r < 0.9 else "")
        internal = rng.random() < 0.02
        u = [f"usr_{uid:06d}", acct, iso(created + timedelta(days=rng.randint(0, 30))), utz,
             "lanternly.io" if internal else "customer.example", "true" if internal else "false"]
        users.append(u)
        acct_users.append((u, rng.betavariate(2, 5)))

    def live_on(day: date) -> bool:
        ts = datetime(day.year, day.month, day.day, 12, tzinfo=UTC)
        return any(s.mrr_at(ts) > 0 or (s.plan == "pln_free" and s.history[0][0] <= ts and (end is None or ts < end))
                   for s, end in subs)

    live = {d: live_on(d) for d in days}
    for u, p in acct_users:
        zone = ZoneInfo(u[3] or tz)
        for d in days:
            if not live[d] or rng.random() > p * (0.3 if d.weekday() >= 5 else 1.0):
                continue
            for _ in range(1 if rng.random() < 0.7 else 2):
                local = datetime(d.year, d.month, d.day, rng.randint(7, 22), rng.randint(0, 59), tzinfo=zone)
                emit(u[0], acct, rng.choice(QUALIFYING), local.astimezone(UTC))
            if rng.random() < 0.3:
                local = datetime(d.year, d.month, d.day, rng.randint(0, 23), rng.randint(0, 59), tzinfo=zone)
                emit(u[0], acct, rng.choice(PASSIVE), local.astimezone(UTC))
    # passive-only users: they open digests but never do real work (must not count as active)
    if rng.random() < 0.15:
        uid += 1
        ghost = [f"usr_{uid:06d}", acct, iso(created), tz, "customer.example", "false"]
        users.append(ghost)
        for d in days[::3]:
            if live[d]:
                emit(ghost[0], acct, "email_digest_opened",
                     datetime(d.year, d.month, d.day, 9, tzinfo=ZoneInfo(tz)).astimezone(UTC))
    if rng.random() < 0.05:
        for d in days[::7]:                                      # system events with no user attached
            emit("", acct, "api_webhook_received", datetime(d.year, d.month, d.day, 3, tzinfo=UTC))

# Deterministic fixtures used by tests/singular/assert_activity_date_is_user_local.sql
fixture_acct = next(a for a, seg, tz, c, subs, t in acct_meta
                    if tz == "Asia/Tokyo" and not t and any(e is None for _, e in subs))
users.append(["usr_fixture_tokyo", fixture_acct, "2025-06-01 00:00:00", "Asia/Tokyo", "customer.example", "false"])
users.append(["usr_fixture_la", fixture_acct, "2025-06-01 00:00:00", "America/Los_Angeles", "customer.example", "false"])
events.append(["evt_fixture_0001", "usr_fixture_tokyo", fixture_acct, "workflow_run", "2026-08-31 20:30:00"])  # 05:30 Sep 1 JST
events.append(["evt_fixture_0002", "usr_fixture_la", fixture_acct, "workflow_run", "2026-09-01 03:00:00"])     # 20:00 Aug 31 PDT

# --------------------------------------------------------------------------- write
print("Writing seeds ...")
write("raw_plans", ["plan_id", "plan_name", "tier_rank", "list_price_usd", "list_price_eur", "list_price_gbp"],
      [list(p) for p in PLANS])
write("raw_accounts", ["account_id", "account_name", "created_at", "segment", "region", "timezone",
                       "billing_currency", "acquisition_channel", "is_test_account", "sales_owner_id"], accounts)
write("raw_subscription_versions",
      ["subscription_id", "version_number", "account_id", "plan_id", "billing_interval", "seats", "currency",
       "unit_price_local", "discount_pct", "mrr_local", "valid_from", "valid_to", "change_reason"],
      [v[:10] + [iso(v[10]), iso(v[11]), v[12]] for v in versions])
write("raw_invoice_lines", ["invoice_id", "account_id", "subscription_id", "issued_at", "currency", "amount",
                            "line_type", "status", "service_period_start", "service_period_end"], invoices)
write("raw_refunds", ["refund_id", "invoice_id", "refunded_at", "currency", "amount", "reason"], refunds)
write("raw_fx_rates_monthly", ["rate_month", "currency", "usd_per_unit"], fx_rows)
write("raw_fx_planning_rates", ["fiscal_year", "currency", "usd_per_unit"], planning_rows)
write("raw_acquisition_costs", ["cost_month", "channel", "cost_category", "amount_usd", "is_acquisition_cost"], acq_rows)
write("raw_cogs", ["cost_month", "cost_category", "amount_usd"], cogs_rows)
write("raw_users", ["user_id", "account_id", "created_at", "timezone", "email_domain", "is_internal"], users)
write("raw_product_events", ["event_id", "user_id", "account_id", "event_name", "occurred_at_utc"], events)
print("Done.")
