# Data Quality Report
**Collections Analytics — 17 raw tables, Jan–Aug 2026**
**Revised**: September 2026 (the August version's duplicate key was wrong; see `CORRECTIONS.md`)

All numbers are produced by `python run_pipeline.py` and saved in `forensics_summary.json`.

---

## Summary

| Issue | Severity | Finding |
|---|---|---|
| A. Duplicate payments | Medium | 500 repeated `payment_id` rows; 325 successful ones worth ₹2.45 Cr (Jan–Jul), ~1.9% of raw successful value, evenly spread. `payment_reference` is **not** unique and must not be used to deduplicate. |
| B. Attribution | High | 63.8% of successful payments had no contact on any channel in the 30 days before. Campaign joins without a time window give campaigns credit for them. |
| C. Time zones | High for hourly analysis | Calls logged in UTC, Asia/Kolkata and Asia/Dubai in equal thirds. |
| D. Disposition codes | High for PTP metrics | `PTP` and `PROMISE_TO_PAY` both mean a promise, in all three versions. 35,000 rows for 28,971 calls. |
| E. Agent identity | High for per-agent metrics | Employee code and name change from row to row for every agent_id. |
| F. Portfolio mix | Low | Early-DPD share of paying accounts 44–47% every month. |
| G. Denominators | Medium | Using `daily_targeting` as the denominator describes different accounts from the payers. |

---

## A. Duplicate payments

| Check | Result |
|---|---|
| Raw payment rows | 25,500 |
| Distinct `payment_id` | 25,000 → 500 duplicate rows (486 exact copies, 14 differ only in reference/method/provider) |
| Duplicate successful rows, Jan–Jul | 325, ₹2.45 Cr |
| `payment_reference` values used more than once | 3,407 |
| ...of those, groups within one account | **0** |
| Successful payments with no reference | 254, ₹1.89 Cr (kept; they are real payments) |

**Treatment:** keep the earliest row per `payment_id` (`stg_payments`). Filter to
`SUCCESS` for recovery (`stg_recovery`). REVERSED rows do not match an earlier
SUCCESS for the same account and amount, so they are separate events and are
simply excluded from recovery.

**Why not `payment_reference`:** rows sharing a reference always belong to
different accounts with different amounts, so they are collisions. Deduplicating
on it deleted 2,703 real payments (₹20.4 Cr), 4% of January's recovery rising to
28.5% of July's, which created a false decline in the August version.

## B. Attribution

Last-touch attribution, 30-day window, one credit per payment:

| Channel | Payments | ₹ Cr | Share |
|---|---|---|---|
| No contact in 30 days | 10,793 | 80.84 | 63.8% |
| WhatsApp | 2,252 | 16.95 | 13.3% |
| Field | 1,452 | 10.93 | 8.6% |
| SMS | 1,336 | 9.94 | 7.9% |
| Voice | 1,085 | 8.19 | 6.4% |

Attribution follows contact volume. Lift (accounts reached by a channel that paid
within 30 days, vs 7.7% of all accounts in any 30-day window): Field +0.23 pp,
SMS +0.21, Voice +0.27, WhatsApp +0.07; every 95% interval includes zero.

## C. Time zones

| Time zone | Calls |
|---|---|
| Asia/Dubai | 30,464 |
| Asia/Kolkata | 30,485 |
| UTC | 30,401 |

**Treatment:** `stg_calls.event_at_utc` (Kolkata −5:30, Dubai −4:00) plus
`hour_ist`. 1,339 calls share an account and timestamp with another call; they
are flagged `is_duplicate` and kept.

## D. Disposition codes

| Code | Rows | Versions it appears in |
|---|---|---|
| PROMISE_TO_PAY | 3,926 | legacy, v1, v2 |
| PTP | 3,904 | legacy, v1, v2 |

Counting only one code misses about half of promises. **Treatment:** both map to
`PTP_MADE` in `stg_dispositions`; one disposition per `call_id` is kept (35,000
rows, 28,971 calls).

## E. Agent identity

1,000 agent_ids, 1,099 employee codes, 10 distinct names across 30,000 rows.
Every agent_id appears on about 30 rows, with a different employee code on
almost every row (29.6 codes per id on average). Grouping by name, as the August
version did, merged 1,000 ids into 10 "agents"; that was an artefact.

**Treatment:** `agent_id` is the key (it is what calls, dispositions and sessions
use); attributes come from the latest row and are flagged unreliable. No
per-person or tenure claims are made until the master data is fixed at source.

## F. Portfolio mix

Share of paying accounts with DPD ≤ 30: 44.1–47.2% each month; DPD > 90:
about 18%. No mix shift that could explain a trend.

## G. Denominators

The August recovery rate divided all paying accounts by accounts in
`daily_targeting` that month, but only 462 of January's 2,374 paying accounts
were targeted in January. **Treatment:** paying-account rate uses the whole
30,000-account portfolio (7.2–8.1% a month, flat).

---

## Assumptions log

1. `payment_id` identifies one payment; verified above. `payment_reference` does not.
2. `agent_id` is the operational key; employee code and name are unreliable in this extract.
3. August 2026 (8 days) is excluded from monthly comparisons.
4. Strategy shift date: 1 April 2026.
5. Portfolio for rates: all 30,000 accounts in `accounts`.
