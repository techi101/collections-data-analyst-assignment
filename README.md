# Collections Data Analyst Assignment

> **Revised September 2026.** I re-audited my August submission and found that
> its headline rested on a wrong duplicate key. [`CORRECTIONS.md`](CORRECTIONS.md)
> explains what was wrong, how I found it and what changed. Everything below is
> the corrected analysis, reproduced from the raw CSVs by `python run_pipeline.py`.

## TL;DR for leadership

The claim that **"recovery improved 11% month-on-month" describes one month, not a trend.**

- March recovery was 11.0% above February, but February was 9.1% below January.
  Across January to July recovery is **flat**: ₹18.72 Cr in January, ₹18.72 Cr in July.
- Real duplicate payments are small: 325 successful rows, ₹2.45 Cr (~1.9%), keyed on `payment_id`.
  `payment_reference` is **not** a unique key: 3,407 references are reused across
  *different* accounts, and deduplicating on it (as my August version did) deleted
  ₹20.4 Cr of real payments and invented a decline.
- Contact rate, promise-kept rate, productivity and portfolio mix are all flat.
- **No channel shows measurable lift**: accounts reached by any channel pay within
  30 days at 7.8–8.0%, the same as the 7.7% baseline. WhatsApp gets the most
  last-touch credit only because it sends the most messages.
- **₹10 Cr recommendation:** don't commit it to one channel on this evidence. Run an
  8-week randomised holdout test first, fix the data at source, then deploy the rest
  to whatever the test shows works. See [`executive_memo.md`](executive_memo.md).

---

## Live dashboard

> **[Open the dashboard](https://techi101.github.io/collections-data-analyst-assignment/dashboard/)**, or open `dashboard/index.html` locally.

---

## Deliverables

| # | Deliverable | Where |
|---|---|---|
| 1 | SQL repository | [`sql_repo/`](sql_repo/): 8 files, run in order by the pipeline |
| 2 | Reproducible pipeline | `python run_pipeline.py`: raw CSVs → `golden_dataset.duckdb`, `golden_metrics.csv`, `forensics_summary.json`, `results/`, `dashboard/data.json` |
| 3 | Data quality report | [`data_quality_report.md`](data_quality_report.md) |
| 4 | Executive memo | [`executive_memo.md`](executive_memo.md) |
| 5 | Dashboard | [`dashboard/`](dashboard/) |
| 6 | Architecture | [`architecture_diagram.md`](architecture_diagram.md) |
| 7 | Corrections log | [`CORRECTIONS.md`](CORRECTIONS.md) |
| 8 | Analysis notebook (August version) | [`notebooks/analysis.ipynb`](notebooks/analysis.ipynb): kept for reference; its numbers are superseded by the pipeline |

---

## Key findings

### Monthly metrics (Jan–Jul 2026; August has 8 days and is excluded)

| Month | Recovery ₹ Cr | MoM | Paying / portfolio | Answer rate | RPC rate | PTP kept | ₹ per agent-hour |
|---|---|---|---|---|---|---|---|
| Jan | 18.72 | — | 7.91% | 20.0% | 76.5% | 24.1% | 16,773 |
| Feb | 17.01 | −9.1% | 7.24% | 19.7% | 76.4% | 25.5% | 16,117 |
| Mar | 18.89 | +11.0% | 8.06% | 19.9% | 77.3% | 24.7% | 16,972 |
| Apr | 17.51 | −7.3% | 7.68% | 19.3% | 77.7% | 25.2% | 16,491 |
| May | 18.43 | +5.2% | 7.81% | 20.4% | 78.5% | 25.3% | 17,008 |
| Jun | 17.56 | −4.7% | 7.62% | 20.4% | 77.1% | 24.7% | 16,403 |
| Jul | 18.72 | +6.7% | 7.78% | 19.4% | 76.2% | 24.6% | 16,748 |

### Data forensics

| Check | Finding |
|---|---|
| A. Duplicate payments | 500 repeated `payment_id` rows; 325 successful, ₹2.45 Cr. `payment_reference` collides across accounts and is not a key. |
| B. Attribution | 63.8% of successful payments had no contact in the prior 30 days (self-cure). |
| C. Time zones | Calls split evenly across UTC, IST and Dubai; normalised to UTC. |
| D. Disposition codes | `PTP` and `PROMISE_TO_PAY` both appear in all 3 versions; counting one misses ~50% of promises. |
| E. Agent identity | Employee code and name change per row for every agent_id; master data can't resolve identity. |
| F. Portfolio mix | Early-DPD share of payers 44–47%, stable. |
| G. Denominators | Targeting-based denominators don't match payers (462 of 2,374 January payers targeted); portfolio used instead. |

### Channels and the strategy shift

| Channel | Last-touch credit (₹ Cr) | Paid within 30 days of first contact | Lift vs 7.7% baseline (95% CI) |
|---|---|---|---|
| WhatsApp | 16.95 | 7.77% | +0.07 pp (−0.30, +0.44) |
| Field | 10.93 | 7.92% | +0.23 pp (−0.20, +0.66) |
| SMS | 9.94 | 7.91% | +0.21 pp (−0.24, +0.66) |
| Voice | 8.19 | 7.96% | +0.27 pp (−0.22, +0.76) |

April strategy shift, difference-in-differences (Field vs WhatsApp+SMS campaigns,
30-day payment after targeting): +1.34 pp, 95% CI −0.25 to +2.93. No detectable effect.

---

## How to run

```bash
pip install duckdb pandas
python run_pipeline.py        # about 5 seconds; prints the tables above
```

Then open `dashboard/index.html`.

## SQL repository

```
sql_repo/
├── 01_staging_payments.sql          # one row per payment_id; recovery = SUCCESS
├── 02_staging_agents.sql            # agent_id as key; conflicting attributes flagged
├── 03_staging_calls.sql             # time zones → UTC; duplicate calls flagged
├── 04_staging_dispositions.sql      # PTP + PROMISE_TO_PAY → PTP_MADE; one per call
├── 05_golden_monthly_metrics.sql    # recovery, paying rate, contact, PTP, productivity
├── 06_channel_analysis.sql          # last-touch attribution + lift vs baseline
├── 07_statistical_investigation.sql # mix effects, Simpson's check, survivorship
└── 08_counterfactual_did.sql        # difference-in-differences for the April shift
```

`archive/` holds the superseded August scripts and outputs.

## Dataset

17 raw CSV files, synthetic, 30,000 accounts, Jan–Aug 2026 (seed 42). Injected
issues include duplicate payments, time-zone conflicts, legacy disposition codes
and inconsistent agent master data.
