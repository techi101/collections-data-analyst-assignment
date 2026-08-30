# Collections Analytics Assignment

## TL;DR

The business claim that **"recovery has improved by 11% month-on-month" is false**.

After building a clean Golden Dataset from the raw 17-table, 12-month collections data, we found:

- **True average MoM recovery change: −7.8%** (not +11%)
- **₹24.3 Cr (22.1%) of recovery was inflated** by 3,752 duplicate payment events
- Recovery rate fell from **39.9% → 29.7%** between January and July 2026
- Contact rates (~30% RPC) and PTP kept rates (~25%) were **stable** — the problem is portfolio health, not operations
- **WhatsApp** is the highest-performing channel and should receive the ₹10 Cr investment

---

## Deliverables

| # | Deliverable | File |
|---|------------|------|
| 1 | SQL Repository | [`sql_repo/`](sql_repo/) (8 files) |
| 2 | Analysis Notebook | [`notebooks/analysis.ipynb`](notebooks/analysis.ipynb) |
| 3 | Golden Dataset Pipeline | [`run_pipeline.py`](run_pipeline.py) → `golden_dataset.duckdb` |
| 4 | Data Quality Report | [`data_quality_report.md`](data_quality_report.md) |
| 5 | Executive Dashboard | [`dashboard/index.html`](dashboard/index.html) |
| 6 | Executive Memo | [`executive_memo.md`](executive_memo.md) |
| 7 | Architecture Diagram | [`architecture_diagram.md`](architecture_diagram.md) |

---

## How to Run

### Prerequisites
```bash
# Python 3.10+ required
pip install duckdb pandas nbformat
```

### Step 1: Build Golden Dataset
```bash
python run_pipeline.py
```
This will:
- Load all 17 CSVs into DuckDB
- Run all staging SQL (deduplication, timezone normalization, entity resolution)
- Create `golden_monthly_metrics` table
- Export `golden_metrics.csv` and `dashboard/data.json`

### Step 2: View Dashboard
Open `dashboard/index.html` in any modern browser — no server required.

### Step 3: Open Notebook
```bash
cd notebooks
jupyter notebook analysis.ipynb
```
Or use VS Code with the Jupyter extension.

---

## SQL Repository Structure

```
sql_repo/
├── 01_staging_payments.sql       # Dedup by payment_reference
├── 02_staging_agents.sql         # Entity resolution (multi-ID agents)
├── 03_staging_calls.sql          # Timezone normalization (UTC/IST/Dubai)
├── 04_staging_dispositions.sql   # Unify legacy + v1 + v2 disposition codes
├── 05_golden_monthly_metrics.sql # Core recovery + contact + PTP metrics
├── 06_channel_analysis.sql       # Channel ROI and WhatsApp funnel
├── 07_statistical_investigation.sql  # Mix effects, Simpson's Paradox, agent tenure
└── 08_counterfactual_did.sql     # Difference-in-Differences counterfactual
```

---

## Key Findings Summary

### Data Forensics
| Check | Status | Impact |
|-------|--------|--------|
| A. Duplicate payments | ✅ FOUND | ₹24.3 Cr inflation (22.1%) |
| B. Attribution errors | ✅ FOUND | 5,035 self-cure payments misattributed to campaigns |
| C. Timezone problems | ✅ FOUND | 91k calls in 3 timezones — hourly analytics broken |
| D. Disposition code changes | ✅ FOUND | PTP undercounted by 33.8% in legacy periods |
| E. Agent identity problems | ✅ FOUND | 10 agents with ~950 duplicate IDs each |
| F. Portfolio mix changes | ⚠️ UNCLEAR | Even DPD distribution (synthetic dataset) |
| G. Denominator manipulation | ✅ CHECKED | Low risk (only 0.7% accounts uncovered) |

### Statistical Investigation
- **Contact Rate**: Stable (~30%) — **not the problem**
- **PTP Kept Rate**: Stable (~24–25%) — **not the problem**
- **Recovery Rate**: Declining 10 pp over 7 months — **portfolio health is the problem**
- **Simpson's Paradox**: Tested — decline is genuine within every DPD bucket, not a composition artefact
- **Survivorship Bias**: Checked — not a material factor (0.7% uncovered accounts)

### Investment Recommendation
**Invest ₹10 Cr in WhatsApp / Digital Engagement**
- WhatsApp leads all channels: ₹41.8 Cr recovered, 3,678 accounts
- Expected incremental recovery: ₹12–18 Cr/year
- ROI: 1.2x–1.8x in 12 months | Break-even: 7–9 months
- Do NOT invest in more agents — recovery/agent-hour fell 25% this year

---

## Dataset
17 raw CSV files (synthetic, ~12 months, 30,000 accounts, seed=42)
