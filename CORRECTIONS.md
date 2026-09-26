# Corrections (September 2026)

I re-audited my own August submission and found that its headline was built on
a wrong assumption. This file records what was wrong, how I found it, and what
changed. Every number below is reproduced by `python run_pipeline.py` from the
17 raw CSVs.

## 1. The duplicate key was wrong (this changed the headline)

**What I did in August.** I treated `payment_reference` as the unique ID of a
payment and kept the earliest row per reference. That removed 3,752 "duplicate"
successful payments and showed recovery falling month after month.

**Why it was wrong.** I never checked the assumption. When I did:

| Check | Result |
|---|---|
| References that appear more than once | 3,407 |
| ...of those, rows from the **same** account | **0** |
| ...amounts that match | 0 |
| `payment_id` values that appear more than once | 500 (486 exact copies, 14 differing only in reference/method/provider) |

Every repeated reference belongs to *different* accounts paying *different*
amounts. They are separate payments whose reference numbers collide. The real
duplicate key is `payment_id`.

**Why it made a fake decline.** References collide more the longer the data
runs, so keeping one payment per reference deleted a growing share of real money:

| Month | Correct recovery (Rs Cr) | August method (Rs Cr) | Real money deleted |
|---|---|---|---|
| Jan | 18.72 | 17.98 | 4.0% |
| Feb | 17.01 | 15.62 | 8.2% |
| Mar | 18.89 | 16.64 | 11.9% |
| Apr | 17.51 | 14.68 | 16.2% |
| May | 18.43 | 14.72 | 20.1% |
| Jun | 17.56 | 13.39 | 23.7% |
| Jul | 18.72 | 13.40 | 28.5% |

In total the August method deleted 2,703 real successful payments worth
Rs 20.4 Cr (Jan–Jul).

**Corrected picture.** Real duplicates are 325 successful rows worth Rs 2.45 Cr
in Jan–Jul, about 1.9% of raw successful value, spread evenly across months.
Recovery is **flat**: Rs 18.72 Cr in January and Rs 18.72 Cr in July.

## 2. The "+11%" claim: true, but misleading (not "false")

March recovery really was 11.0% above February, in the raw data and in the
clean data. But February was 9.1% below January, and the months after March
alternate between up and down. Feb–Jul month-on-month changes average +0.3%.
The claim describes one rebound month, not an improvement. My August version
called it "false" and blamed duplicates in March; duplicates are not
concentrated in March.

## 3. The ₹10 Cr WhatsApp recommendation was not supported

The August channel query joined campaigns to payments on account with no time
window, so each payment was counted once for every campaign that ever targeted
the account (the channel table summed to far more than total recovery).
Corrected, two ways:

- **Last-touch attribution** (each payment credited once, to the last contact
  in the 30 days before it): 63.8% of payments had no contact at all.
  WhatsApp gets the most credit (Rs 16.95 Cr) because it sends the most
  messages.
- **Lift** (did contact change behaviour?): accounts reached by each channel
  paid within 30 days at 7.8–8.0%, against a 7.7% baseline for all accounts.
  Every 95% confidence interval includes zero.

So no channel shows a measurable effect in this data, and the data cannot pick
a winner for Rs 10 Cr. The corrected recommendation is a randomised holdout
test before a large commitment (see `executive_memo.md`).

## 4. Other corrections

| Item | August claim | Corrected |
|---|---|---|
| Recovery rate | 39.9% → 29.7% | Numerator (all paying accounts) and denominator (accounts targeted that month) described different people: only 462 of January's 2,374 paying accounts were targeted. Paying accounts / whole portfolio is flat at 7.2–8.1% a month. |
| Agent productivity | Fell 25% | Flat, Rs 16,117–17,008 per agent-hour. |
| PTP undercount | 33.8% | Both `PTP` and `PROMISE_TO_PAY` appear in all three schema versions. Counting only one misses about 50% (3,926 of 7,830). |
| Agent identity | 10 agents with ~950 IDs each | An artefact of grouping by name (the table has only 10 names). Each agent_id's employee code and name change from row to row, so the master data cannot resolve identity. agent_id is now the key. |
| Self-cure | 5,035 payments | 10,793 of 16,918 successful payments (63.8%) had no contact on any channel in the prior 30 days. |
| Strategy shift (DiD) | "Reduced Field recovery" (never computed) | Computed properly: +1.3 pp for Field vs digital, 95% CI −0.2 to +2.9 pp. No detectable effect. |
| Dispositions | ~39,600 rows | 35,000 rows for 28,971 calls; one disposition per call is kept. |
| Pipeline | Needed tables from an earlier run | `run_pipeline.py` now rebuilds everything from the raw CSVs in about 5 seconds. |

## What I would do differently

Check every key before deduplicating on it: for a candidate key, look at a few
groups that share it and confirm they describe the same thing. Here, one query
("do rows sharing a reference share an account?") would have caught it in
August.

Superseded scripts and outputs from the August version are kept in `archive/`
for reference.
