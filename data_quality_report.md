# Data Quality Report
**Collections Analytics — 12-Month Dataset**  
**Generated**: August 2026 | **Analyst**: Collections Analytics Team

---

## Executive Summary

The raw dataset of 17 tables contained **7 categories of data quality issues**, all of which were intentionally injected. The most critical issue — duplicate payment events — caused the business to overstate recovery by **₹24.3 Cr (22.1%)**, which is the primary source of the falsely reported 11% improvement.

---

## Issue A: Duplicate Payment Events *(CRITICAL)*

| Attribute | Value |
|-----------|-------|
| **Detection method** | `COUNT(*) > 1` partitioned by `payment_reference` |
| **Raw SUCCESS events** | 17,880 |
| **Unique payment references** | 14,128 |
| **Duplicate events** | 3,752 |
| **Inflated recovery (raw)** | ₹134.1 Cr |
| **True recovery (deduplicated)** | ₹109.8 Cr |
| **Inflation** | ₹24.3 Cr **(+22.1%)** |
| **Root cause** | Payment retry logic logging same transaction multiple times on failure→retry |
| **Treatment** | Keep earliest `event_at` per `payment_reference` (table: `stg_payments`) |
| **Business impact** | The March raw data showed +11% MoM. After deduplication, March shows only +6.6% — and on a declining trend overall |

---

## Issue B: Attribution Errors *(HIGH)*

| Attribute | Value |
|-----------|-------|
| **Detection method** | Payments with no prior call OR WhatsApp event in same account |
| **Affected payments** | 5,035 SUCCESS payments |
| **As % of total** | ~34% of all recoveries |
| **Root cause** | System attributes payment to "last campaign touched" regardless of causal order |
| **Treatment** | Tag these as `self_cure = TRUE` in golden dataset; exclude from channel attribution |
| **Business impact** | Channel-level ROI calculations (esp. WhatsApp) are overstated if self-cure payments are included |

---

## Issue C: Timezone Problems *(HIGH)*

| Attribute | Value |
|-----------|-------|
| **Detection method** | `SELECT DISTINCT timezone FROM calls` — found 3 values |
| **Calls in UTC** | 30,401 (33.3%) |
| **Calls in Asia/Kolkata** | 30,485 (33.4%) |
| **Calls in Asia/Dubai** | 30,464 (33.3%) |
| **Root cause** | Multiple telephony vendors report timestamps in their own reference timezone |
| **Treatment** | All `event_at` normalized to UTC in `stg_calls`; `hour_ist` derived for IST business-hours analysis |
| **Business impact** | "Best time to call" analysis using raw `event_at` is **completely wrong** — a 10am UTC call appears as a 10am IST call, but is actually 3:30pm IST |

---

## Issue D: Disposition Code Schema Changes *(HIGH)*

| Attribute | Value |
|-----------|-------|
| **Detection method** | `SELECT DISTINCT disposition_code, disposition_version FROM call_dispositions` |
| **Versions found** | `legacy`, `v1`, `v2` |
| **Critical conflict** | `PROMISE_TO_PAY` (legacy) = `PTP` (v1/v2) — same metric, different codes |
| **Legacy PTP events** | 1,332 |
| **Modern PTP events** | 2,608 |
| **Undercount if not unified** | **33.8%** of all PTPs are missed |
| **Treatment** | `normalized_code = 'PTP_MADE'` for both codes in `stg_dispositions` |
| **Business impact** | PTP Rate was materially understated in legacy reporting periods (pre-v1 rollout) |

---

## Issue E: Agent Identity Problems *(MEDIUM)*

| Attribute | Value |
|-----------|-------|
| **Detection method** | `COUNT(DISTINCT agent_id) > 1` grouped by `agent_name` |
| **Conflicted agents** | 10 |
| **Duplicate IDs per agent** | ~946–958 per conflicted agent |
| **Root cause** | Vendor system re-registers agents with new `agent_id` on password reset or device change |
| **Treatment** | Group by `agent_name` + `employee_code`, assign `MIN(agent_id)` as canonical in `stg_agents` |
| **Business impact** | Recovery-per-agent and RPC-per-agent metrics are artificially diluted across duplicate ghost accounts |

---

## Issue F: Portfolio Mix Changes *(LOW — Dataset Artifact)*

| Attribute | Value |
|-----------|-------|
| **Detection method** | DPD distribution, `account_status_history` monthly active counts |
| **Finding** | DPD buckets are uniformly distributed (2,685–2,770 per bucket) — synthetic dataset characteristic |
| **Real-world concern** | In live data, check if DPD mix shifts toward higher-DPD accounts month-on-month (harder to collect) |
| **Treatment** | Flag for validation with real data; current analysis treats DPD mix as stable |
| **Business impact** | If late-DPD accounts increase without tracking, denominator stays flat but recovery declines — looks like performance drop but is actually portfolio change |

---

## Issue G: Denominator Manipulation *(LOW)*

| Attribute | Value |
|-----------|-------|
| **Detection method** | Accounts in `accounts` table not present in any contact event |
| **Accounts with no contact** | 207 (0.7% of portfolio) |
| **Finding** | No systemic suppression of uncontactable accounts from denominators |
| **Residual risk** | If reporting uses `daily_targeting` as denominator (not full `accounts` table), accounts without targeting records are silently excluded |
| **Treatment** | Golden dataset uses `accounts` as the denominator anchor, not `daily_targeting` |
| **Business impact** | Conversion rates could be inflated by ~0.5–1 pp if untargeted accounts are excluded |

---

## Summary: Raw → Rejected → Golden Dataset

| Table | Raw Records | Rejected/Corrected | Golden Records | Issue |
|-------|------------|-------------------|----------------|-------|
| `payments` | 25,500 | 4,678 duplicates removed | 20,822 | Duplicate payment refs |
| `borrowers` | ~30,000+ | 8,566 deduplicated | ~21,434 | Duplicate borrower_ids |
| `agents` | ~10,000+ | 10 identity clusters collapsed | Canonical set | Multi-ID per agent |
| `calls` | 91,350 | ~100 duplicate events | 91,250 | Same account+timestamp |
| `call_dispositions` | ~39,600 | 0 removed, codes unified | 39,600 (normalized) | 3 schema versions |

---

## Assumptions Log

1. `payment_reference` is a stable, system-generated unique identifier for each financial transaction (not per-attempt).
2. `employee_code` is the stable human identifier for an agent (payroll number, unchanged across vendor changes).
3. August 2026 data is partial and excluded from all MoM calculations.
4. Strategy shift date assumed as **April 1, 2026** based on `strategy_version` field changing from `legacy`/`v1` to `v2`/`v3`.
5. "Active portfolio" is defined as all accounts present in `daily_targeting` for a given month (not just accounts with a SUCCESS payment).
