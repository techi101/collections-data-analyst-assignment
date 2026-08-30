# Collections Data Analyst Assignment

## 🔴 TL;DR — Bottom Line for Leadership

The business claim that **"recovery has improved by 11% month-on-month" is false.**

After forensic analysis of 17 raw tables, we found:
- **₹24.3 Cr (22.1%) of recovery was inflated** by 3,752 duplicate payment events
- **True average MoM change: −7.8%** (not +11%)
- Recovery rate fell from **39.9% → 29.7%** (Jan → Jul 2026)
- Contact rates (~30% RPC) were stable — the problem is **portfolio health, not operations**
- **WhatsApp** is the highest-performing channel (₹41.8 Cr recovered) → **recommended for ₹10 Cr investment**

---

## 📊 Live Executive Dashboard (CEO View — 60 seconds)

> **[🖥️ Open Executive Dashboard](https://techi101.github.io/collections-data-analyst-assignment/dashboard/)**
>
> Open this link in any browser — no login or installation required.

---

## 📁 Deliverables Index

| # | Deliverable | How to View |
|---|-------------|-------------|
| 1 | **SQL Repository** | Browse [`sql_repo/`](sql_repo/) — 8 production SQL files |
| 2 | **Analysis Notebook** | View [`notebooks/analysis.ipynb`](notebooks/analysis.ipynb) — renders on GitHub |
| 3 | **Golden Dataset Pipeline** | Run `python run_pipeline.py` to reproduce `golden_dataset.duckdb` |
| 4 | **Data Quality Report** | Read [`data_quality_report.md`](data_quality_report.md) |
| 5 | **Executive Dashboard** | **[Live link](https://techi101.github.io/collections-data-analyst-assignment/dashboard/)** or open `dashboard/index.html` locally |
| 6 | **Executive Memo** | Read [`executive_memo.md`](executive_memo.md) |
| 7 | **Architecture Diagram** | Read [`architecture_diagram.md`](architecture_diagram.md) — Mermaid diagram renders on GitHub |

---

## 🔍 Key Findings Summary

### Data Forensics (Part 2)

| Check | Found? | Impact |
|-------|--------|--------|
| A. Duplicate payments | ✅ YES | 3,752 events · ₹24.3 Cr inflation (22.1%) |
| B. Attribution errors | ✅ YES | 5,035 self-cure payments wrongly attributed to campaigns |
| C. Timezone problems | ✅ YES | 91k calls in 3 timezones (UTC/IST/Dubai) — hourly analytics broken |
| D. Disposition code changes | ✅ YES | 3 schema versions — PTP undercounted by 33.8% |
| E. Agent identity problems | ✅ YES | 10 agents with ~950 duplicate IDs each |
| F. Portfolio mix changes | ⚠️ UNCLEAR | Uniform DPD distribution (synthetic dataset) |
| G. Denominator manipulation | ✅ CHECKED | Low risk — only 0.7% accounts uncovered |

### Statistical Investigation (Part 3)
- **Contact Rate**: Stable ~30% ✅ — not the problem
- **PTP Kept Rate**: Stable ~24–25% ✅ — not the problem
- **Recovery Rate**: Fell 10 pp (39.9% → 29.7%) ❌ — portfolio health declining
- **Simpson's Paradox**: Tested — decline is genuine within every DPD bucket, not a mix artefact
- **Survivorship Bias**: Checked — not a material factor

### Counterfactual (Part 4)
- **Method**: Difference-in-Differences (DiD)
- **Finding**: The mid-year strategy shift (routing late-DPD accounts to Field) **reduced** Field recovery vs. the counterfactual baseline

### Investment Recommendation (₹10 Cr)
**→ WhatsApp / Digital Engagement**

| Parameter | Estimate |
|-----------|----------|
| Accounts recovered (Jan–Jul) | 3,678 (highest of all channels) |
| Total recovered | ₹41.8 Cr (highest of all channels) |
| Expected incremental recovery | ₹12–18 Cr / year |
| ROI | 1.2x–1.8x in 12 months |
| Break-even | 7–9 months |
| Confidence | High (Strong Evidence) |

---

## ▶️ How to Run Locally

### Prerequisites
```bash
pip install duckdb pandas nbformat
```

### Step 1 — Rebuild the Golden Dataset
```bash
python run_pipeline.py
```
This loads all 17 CSVs into DuckDB, runs all staging SQL (dedup, timezone fix, entity resolution), and outputs `golden_dataset.duckdb` and `golden_metrics.csv`.

### Step 2 — Open the Dashboard
```bash
# Just double-click dashboard/index.html in your file explorer
# OR open this link:
# https://techi101.github.io/collections-data-analyst-assignment/dashboard/
```

### Step 3 — Open the Notebook
```bash
cd notebooks
jupyter notebook analysis.ipynb
```

---

## 🗂️ SQL Repository Structure

```
sql_repo/
├── 01_staging_payments.sql          # Dedup by payment_reference (removes ₹24.3 Cr inflation)
├── 02_staging_agents.sql            # Entity resolution — multi-ID agents collapsed
├── 03_staging_calls.sql             # Timezone normalization (UTC/IST/Dubai → UTC)
├── 04_staging_dispositions.sql      # Unify legacy + v1 + v2 disposition codes
├── 05_golden_monthly_metrics.sql    # Recovery Rate, Contact Rate, PTP Rate, Recovery/Agent-Hour
├── 06_channel_analysis.sql          # Channel ROI + WhatsApp funnel + Field conversion
├── 07_statistical_investigation.sql # Mix effects, Simpson's Paradox, agent tenure analysis
└── 08_counterfactual_did.sql        # Difference-in-Differences counterfactual
```

---

## 📦 Dataset
17 raw CSV files · Synthetic · ~12 months · 30,000 accounts · Seed = 42  
Intentional issues: duplicates, missing values, timezone conflicts, legacy schemas, duplicate payments, multi-ID agents.
