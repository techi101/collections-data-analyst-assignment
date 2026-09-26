# Executive Memo

**To:** Leadership Team
**From:** Collections Analytics
**Date:** September 2026 (revised; see `CORRECTIONS.md`)
**Re:** Is recovery improving, and where should ₹10 Cr go?

---

## 1. What happened?

**The reported "11% month-on-month improvement" is one month, not a trend.**

- March recovery was 11.0% above February. That is real. But February was
  9.1% below January, and the months since alternate up and down.
- Across January to July, recovery is **flat**: ₹18.72 Cr in January and
  ₹18.72 Cr in July. Month-on-month changes from February to July average +0.3%.
- The data needed one correction: 325 duplicated successful payments
  (₹2.45 Cr, about 1.9%) were removed, keyed on `payment_id`. They are spread
  evenly across months and do not explain the March number.

| Month | Recovery (₹ Cr) | MoM | Accounts paying | Paying / portfolio |
|---|---|---|---|---|
| Jan | 18.72 | — | 2,374 | 7.9% |
| Feb | 17.01 | −9.1% | 2,173 | 7.2% |
| Mar | 18.89 | +11.0% | 2,419 | 8.1% |
| Apr | 17.51 | −7.3% | 2,304 | 7.7% |
| May | 18.43 | +5.2% | 2,344 | 7.8% |
| Jun | 17.56 | −4.7% | 2,286 | 7.6% |
| Jul | 18.72 | +6.7% | 2,335 | 7.8% |

## 2. Why?

Nothing in operations changed:

| Driver | Finding | Evidence level |
|---|---|---|
| Contact | Answer rate 19–20%, right-party-contact 76–79% of dispositioned calls, flat | Fact |
| Promises | Promise-kept rate 24–26%, flat | Fact |
| Productivity | ₹16,100–17,000 recovered per agent-hour, flat | Fact |
| Portfolio mix | Share of paying accounts in early DPD 44–47%, flat | Fact |
| April strategy shift | Field vs digital difference-in-differences +1.3 pp, 95% CI −0.2 to +2.9 | No detectable effect |
| Month-to-month swings | Alternating ±5–11% with no driver above | Most consistent with normal variation |

Reporting problems that would mislead a dashboard (fixed in the pipeline):
- `PTP` and `PROMISE_TO_PAY` both mean a promise, in all three schema
  versions; counting one misses about half of promises.
- Calls are logged in three time zones; hourly analysis needs UTC conversion.
- Agent master data changes employee code and name from row to row, so
  per-agent league tables cannot be trusted until it is fixed at source.

## 3. How confident are we?

| Claim | Confidence |
|---|---|
| Recovery is flat Jan–Jul | High: same result with or without the duplicate correction |
| The +11% is a single rebound month | High |
| No channel shows measurable lift | Moderate: observational data; every 95% interval includes zero |
| The April shift had no detectable effect | Moderate: parallel-trends assumption, small Field sample |

Limits: synthetic dataset, 7 full months (August has 8 days), no randomised
control group, so causal claims about channels are not possible from this data.

## 4. What should we do with ₹10 Cr?

**Do not commit ₹10 Cr to one channel on this evidence.** WhatsApp is credited
with the most recovery (₹16.95 Cr under last-touch attribution) only because it
sends the most messages. Accounts reached by any channel pay within 30 days at
7.8–8.0%, the same as the 7.7% baseline for all accounts.

Recommended split:

1. **Up to ₹1.5 Cr (proposed): an 8-week randomised holdout test.** Randomly
   hold out 20% of the accounts each channel would contact and compare 30-day
   payment rates. With about 20,000 accounts per channel and a 7.8% base rate,
   this detects a lift of about 1.3 percentage points (80% power, 5% level).
   This is what turns "WhatsApp gets the most credit" into "WhatsApp causes
   recovery".
2. **Up to ₹1.5 Cr (proposed): data fixes.** Payment IDs enforced at ingestion, one disposition
   taxonomy, UTC timestamps, a clean agent master. Without these, the next
   report will repeat this review's problems.
3. **The remaining ₹7 Cr or more: held, then deployed** to whichever channel the test shows works,
   in proportion to measured lift per rupee.

**Why not hire more agents?** Productivity per agent-hour is flat and contact
shows no measurable lift, so more calls are unlikely to add recovery until the
test says otherwise.
