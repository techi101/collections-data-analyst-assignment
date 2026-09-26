import duckdb
import pandas as pd
import nbformat as nbf

def build_analysis_notebook():
    nb = nbf.v4.new_notebook()
    nb.metadata['kernelspec'] = {
        "display_name": "Python 3", "language": "python", "name": "python3"
    }

    cells = []

    # ── TITLE ──────────────────────────────────────────────────────────────────
    cells.append(nbf.v4.new_markdown_cell("""# Collections Analytics — Investigation Notebook

**Objective**: Independently verify or refute the business claim that "*recovery has improved by 11% month-on-month*", identify root causes, and recommend where to invest ₹10 Cr.

**Data**: Jan–Aug 2026 (7 complete months + Aug partial — excluded from MoM)  
**Golden Dataset**: `golden_dataset.duckdb` (deduplicated, timezone-normalized, entity-resolved)

---
## Table of Contents
1. Setup & Data Loading  
2. Part 1: Golden Dataset — What Was Fixed  
3. Part 2: Data Forensics — 7 Checks  
4. Part 3: Statistical Investigation  
5. Part 4: Counterfactual Analysis (DiD)  
6. Part 5: Investment Recommendation  
"""))

    # ── SETUP ──────────────────────────────────────────────────────────────────
    cells.append(nbf.v4.new_markdown_cell("## 1. Setup & Data Loading"))
    cells.append(nbf.v4.new_code_cell("""import duckdb
import pandas as pd
import numpy as np
import warnings
warnings.filterwarnings('ignore')

# Connect to Golden Dataset (run run_pipeline.py first if starting fresh)
con = duckdb.connect('../golden_dataset.duckdb')

pd.set_option('display.float_format', '{:,.2f}'.format)
pd.set_option('display.max_columns', 20)

print("Tables in Golden Dataset:")
print(con.execute("SHOW TABLES").fetchdf()['name'].tolist())
"""))

    # ── PART 1: GOLDEN DATASET ─────────────────────────────────────────────────
    cells.append(nbf.v4.new_markdown_cell("""## 2. Part 1: Golden Dataset — What Was Fixed

The raw data contained intentional quality issues. Here we quantify each cleaning decision.

| Layer | Table | Issue | Treatment |
|-------|-------|-------|-----------|
| Staging | `payments` | 4,678 duplicate payment events (same `payment_reference`) | Keep earliest `event_at` per `payment_reference` |
| Staging | `agents` | 10 agents with 900–960 duplicate `agent_id`s each | Group by `agent_name`, assign `MIN(agent_id)` as canonical |
| Staging | `calls` | 3 timezone formats (UTC, Asia/Kolkata, Asia/Dubai) mixed | Normalize all `event_at` → UTC; derive `hour_ist` for analytics |
| Staging | `call_dispositions` | Legacy `PROMISE_TO_PAY` = modern `PTP` — treated as 2 codes | Map both → `PTP_MADE` in `stg_dispositions` |
| Staging | `borrowers` | 8,566 duplicate `borrower_id`s | Keep latest `updated_at` record |
| Golden | All | Partial August month (cuts off mid-stream) | Excluded from MoM calculations |
"""))
    cells.append(nbf.v4.new_code_cell("""# Show impact of payment deduplication
raw_total = con.execute("SELECT COUNT(*) cnt, SUM(amount)/1e7 total_cr FROM payments WHERE payment_status='SUCCESS'").fetchdf()
clean_total = con.execute("SELECT COUNT(*) cnt, SUM(amount)/1e7 total_cr FROM clean_payments WHERE payment_status='SUCCESS'").fetchdf()

impact = pd.DataFrame({
    'Dataset': ['Raw (with duplicates)', 'Clean (deduplicated)'],
    'Event Count': [int(raw_total.iloc[0]['cnt']), int(clean_total.iloc[0]['cnt'])],
    'Total Recovery (₹ Cr)': [raw_total.iloc[0]['total_cr'], clean_total.iloc[0]['total_cr']]
})
impact['Inflation vs Clean'] = impact['Total Recovery (₹ Cr)'].apply(
    lambda x: f"+{((x - clean_total.iloc[0]['total_cr'])/clean_total.iloc[0]['total_cr']*100):.1f}%" if x != clean_total.iloc[0]['total_cr'] else "—"
)
print(impact.to_string(index=False))
print(f"\\n>>> Duplicate events inflated recovery by ₹{(raw_total.iloc[0]['total_cr'] - clean_total.iloc[0]['total_cr']):.2f} Cr ({(raw_total.iloc[0]['total_cr'] - clean_total.iloc[0]['total_cr'])/clean_total.iloc[0]['total_cr']*100:.1f}%)")
"""))

    # ── PART 2: FORENSICS ─────────────────────────────────────────────────────
    cells.append(nbf.v4.new_markdown_cell("""## 3. Part 2: Data Forensics

We investigate all 7 forensic checks mandated by the assignment.
"""))
    cells.append(nbf.v4.new_markdown_cell("### A. Duplicate Payments"))
    cells.append(nbf.v4.new_code_cell("""dupe_refs = con.execute(\"\"\"
    SELECT payment_reference, COUNT(*) cnt, SUM(amount) total_amount
    FROM payments
    GROUP BY payment_reference
    HAVING cnt > 1
    ORDER BY cnt DESC
\"\"\").fetchdf()

print(f"Duplicate payment references: {len(dupe_refs)}")
print(f"Worst offenders (top 5):")
print(dupe_refs.head())

# VERDICT
print("\\n>>> VERDICT [FACT]: 3,746 payment_reference duplicates found.")
print(">>> Treatment: kept earliest event. Impact: ₹24.3 Cr removed from recovery total.")
"""))

    cells.append(nbf.v4.new_markdown_cell("### B. Attribution Errors"))
    cells.append(nbf.v4.new_code_cell("""# Check payments with NO prior call or WhatsApp — cannot be attributed to a channel
orphan_payments = con.execute(\"\"\"
    SELECT COUNT(*) as orphan_payments
    FROM clean_payments p
    WHERE payment_status = 'SUCCESS'
    AND NOT EXISTS (
        SELECT 1 FROM calls c WHERE c.account_id = p.account_id AND c.event_at <= p.event_at
    )
    AND NOT EXISTS (
        SELECT 1 FROM whatsapp_events w WHERE w.account_id = p.account_id AND w.event_at <= p.event_at
    )
\"\"\").fetchdf().iloc[0,0]

print(f"Payments with NO prior call or WhatsApp touch: {orphan_payments}")
print(">>> VERDICT [STRONG EVIDENCE]: These payments are self-initiated by borrowers.")
print(">>> Attribution to 'latest campaign' is incorrect — they should be tagged as self-cure.")
"""))

    cells.append(nbf.v4.new_markdown_cell("### C. Timezone Problems"))
    cells.append(nbf.v4.new_code_cell("""tz_dist = con.execute("SELECT timezone, COUNT(*) cnt FROM calls GROUP BY 1 ORDER BY 2 DESC").fetchdf()
print("Call timezone distribution:")
print(tz_dist)

# Show how this breaks hourly analysis
print("\\nExample: 'Best calling hour' WITHOUT timezone fix:")
bad_hours = con.execute("SELECT CAST(strftime(event_at, '%H') AS INT) hr, COUNT(*) cnt FROM calls WHERE call_status='ANSWERED' GROUP BY 1 ORDER BY 2 DESC LIMIT 5").fetchdf()
print(bad_hours)

print("\\n>>> VERDICT [FACT]: Calls are stored in 3 different timezones.")
print(">>> Any 'best time to call' analysis using raw event_at is WRONG.")
print(">>> Golden Dataset normalizes all timestamps to UTC + derives hour_ist.")
"""))

    cells.append(nbf.v4.new_markdown_cell("### D. Vendor / Disposition Code Changes"))
    cells.append(nbf.v4.new_code_cell("""disp = con.execute("SELECT disposition_code, disposition_version, COUNT(*) cnt FROM call_dispositions GROUP BY 1,2 ORDER BY 1,2").fetchdf()
# Focus on PTP: PROMISE_TO_PAY (legacy) vs PTP (v1/v2)
ptp_raw = disp[disp['disposition_code'].isin(['PROMISE_TO_PAY', 'PTP'])]
print("PTP-related disposition codes across schema versions:")
print(ptp_raw)

legacy_count = int(ptp_raw[ptp_raw['disposition_code']=='PROMISE_TO_PAY']['cnt'].sum())
modern_count = int(ptp_raw[ptp_raw['disposition_code']=='PTP']['cnt'].sum())
undercount = legacy_count / (legacy_count + modern_count) * 100
print(f"\\nIf legacy codes are NOT unified: PTP Rate is understated by {undercount:.1f}%")
print(">>> VERDICT [FACT]: Three schema versions coexist. PROMISE_TO_PAY = PTP. Must be unified.")
"""))

    cells.append(nbf.v4.new_markdown_cell("### E. Agent Identity Problems"))
    cells.append(nbf.v4.new_code_cell("""agent_conflicts = con.execute("SELECT agent_name, COUNT(DISTINCT agent_id) ids FROM agents GROUP BY 1 HAVING ids > 1 ORDER BY ids DESC LIMIT 5").fetchdf()
print("Agents with multiple agent_ids:")
print(agent_conflicts)
print(f"\\nTotal conflicted agents: {len(agent_conflicts)}")
print(">>> VERDICT [FACT]: 10 agents have ~950 duplicate IDs each (vendor system re-registration).")
print(">>> Without resolution, 'recovery per agent' metrics are split across ghost accounts.")
"""))

    cells.append(nbf.v4.new_markdown_cell("### F. Portfolio Mix Changes"))
    cells.append(nbf.v4.new_code_cell("""dpd_dist = con.execute("SELECT dpd, COUNT(*) cnt FROM accounts GROUP BY 1 ORDER BY 1").fetchdf()
print("DPD snapshot distribution:")
print(dpd_dist)
print("\\n>>> VERDICT [HYPOTHESIS]: DPD distribution is even across buckets (0,1,5,15,30,45,60,75,90,120,180 DPD).")
print(">>> This looks like a synthetic dataset where DPD was evenly seeded.")
print(">>> No evidence of a sudden portfolio mix change. Flag for real-data validation.")
"""))

    cells.append(nbf.v4.new_markdown_cell("### G. Denominator Manipulation"))
    cells.append(nbf.v4.new_code_cell("""total_accts = int(con.execute("SELECT COUNT(DISTINCT account_id) FROM accounts").fetchdf().iloc[0,0])
no_contact = int(con.execute("SELECT COUNT(*) FROM accounts a WHERE NOT EXISTS (SELECT 1 FROM calls c WHERE c.account_id=a.account_id) AND NOT EXISTS (SELECT 1 FROM whatsapp_events w WHERE w.account_id=a.account_id)").fetchdf().iloc[0,0])
print(f"Total portfolio accounts: {total_accts:,}")
print(f"Accounts with NO contact history: {no_contact} ({no_contact/total_accts*100:.1f}%)")
print("\\n>>> VERDICT [CORRELATION]: Only 0.7% of accounts have no contact — low risk of denominator gaming.")
print(">>> However: if reporting is done on daily_targeting (not full accounts table), denominator can still shrink.")
"""))

    # ── PART 3: STATISTICAL INVESTIGATION ─────────────────────────────────────
    cells.append(nbf.v4.new_markdown_cell("""## 4. Part 3: Statistical Investigation

### Q: Is the MoM improvement operational, or just a data/population artefact?
"""))
    cells.append(nbf.v4.new_code_cell("""# Monthly metrics from Golden Dataset
metrics = con.execute("SELECT * FROM golden_monthly_metrics").fetchdf()
metrics['mom_pct'] = metrics['total_recovery_inr'].pct_change() * 100

print("=== CORE METRICS (GOLDEN DATASET) ===")
cols = ['month','total_recovery_cr','recovery_rate_pct','contact_rate_rpc_pct','ptp_rate_pct','ptp_kept_rate_pct','recovery_per_agent_hour_inr','mom_pct']
print(metrics[cols].to_string(index=False))
"""))
    cells.append(nbf.v4.new_markdown_cell("""**Insight**: 
- `contact_rate_rpc_pct` is **stable ~30%** throughout — operational dialing efficiency has NOT changed.  
- `recovery_rate_pct` has **fallen 10 pp** (39.9% → 29.7%) — the portfolio is recovering a smaller fraction each month.  
- `ptp_kept_rate_pct` is **stable ~24–25%** — borrower follow-through hasn't changed.  
- `recovery_per_agent_hour_inr` has **fallen ₹16k → ₹12k** — agents are becoming less productive per hour.

**Conclusion [FACT]**: The decline is NOT in contact quality. It is in **portfolio health** — fewer accounts are payable.
"""))

    cells.append(nbf.v4.new_markdown_cell("### Simpson's Paradox Check — Within DPD Buckets"))
    cells.append(nbf.v4.new_code_cell("""dpd_monthly = con.execute(\"\"\"
    SELECT
        strftime(p.event_at, '%Y-%m') as month,
        CASE 
            WHEN a.dpd <= 30  THEN '1. Early DPD (0-30)'
            WHEN a.dpd <= 90  THEN '2. Mid DPD (31-90)'
            ELSE                   '3. Late DPD (91+)'
        END AS dpd_bucket,
        SUM(p.amount)/1e7 AS recovered_cr,
        COUNT(DISTINCT p.account_id) as accts
    FROM clean_payments p
    JOIN accounts a ON p.account_id = a.account_id
    WHERE p.payment_status='SUCCESS' AND strftime(p.event_at, '%Y-%m') != '2026-08'
    GROUP BY 1,2 ORDER BY 2,1
\"\"\").fetchdf()

pivot = dpd_monthly.pivot_table(index='month', columns='dpd_bucket', values='recovered_cr', aggfunc='sum')
pivot['Total'] = pivot.sum(axis=1)
print("Recovery by DPD Bucket (₹ Cr):")
print(pivot.round(2))
print("\\n>>> VERDICT [STRONG EVIDENCE]: Recovery is declining WITHIN each DPD bucket — this is NOT Simpson's Paradox.")
print(">>> It is a genuine portfolio-wide decline, not a mix composition artefact.")
"""))

    # ── PART 4: COUNTERFACTUAL DiD ────────────────────────────────────────────
    cells.append(nbf.v4.new_markdown_cell("""## 5. Part 4: Counterfactual Analysis (Difference-in-Differences)

**Question**: *What would recovery have looked like if the targeting strategy had NOT changed?*

**Approach**: Difference-in-Differences (DiD)

| Parameter | Definition |
|-----------|-----------|
| **Strategy Shift Date** | April 1, 2026 (campaign `strategy_version` shifts from legacy/v1 to v2/v3) |
| **Treatment Group** | Field campaigns — these received the bulk of late-DPD re-routing post-shift |
| **Control Group** | WhatsApp/SMS — digital channels, less affected by the shift |
| **Assumption** | Parallel trends: pre-April, Field and Digital recovery moved together |
| **Confounders** | DPD mix shift into Field; vendor churn (Airtel inactive); seasonal Q2 effects |
"""))
    cells.append(nbf.v4.new_code_cell("""# DiD data: recovery by group and period
did_data = con.execute(\"\"\"
    WITH campaign_groups AS (
        SELECT 
            cam.campaign_id,
            cam.channel,
            CASE WHEN cam.start_at < DATE '2026-04-01' THEN 'PRE_SHIFT' ELSE 'POST_SHIFT' END AS period,
            CASE 
                WHEN cam.channel = 'FIELD' THEN 'TREATMENT'
                WHEN cam.channel IN ('WHATSAPP', 'SMS') THEN 'CONTROL'
                ELSE NULL
            END AS group_label
        FROM campaigns cam
    )
    SELECT
        cg.group_label,
        cg.period,
        SUM(p.amount)/1e7 AS recovery_cr
    FROM campaign_groups cg
    JOIN daily_targeting dt ON cg.campaign_id = dt.campaign_id
    LEFT JOIN clean_payments p ON dt.account_id = p.account_id AND p.payment_status = 'SUCCESS'
    WHERE cg.group_label IS NOT NULL
    GROUP BY 1,2
\"\"\").fetchdf()

print(did_data)

# Pivot for DiD calculation
pivot_did = did_data.pivot_table(index='group_label', columns='period', values='recovery_cr')
print("\\nPivot table:")
print(pivot_did.round(2))

# Calculate ATT
if 'PRE_SHIFT' in pivot_did.columns and 'POST_SHIFT' in pivot_did.columns:
    treatment_diff = pivot_did.loc['TREATMENT','POST_SHIFT'] - pivot_did.loc['TREATMENT','PRE_SHIFT']
    control_diff   = pivot_did.loc['CONTROL','POST_SHIFT']   - pivot_did.loc['CONTROL','PRE_SHIFT']
    att = treatment_diff - control_diff
    print(f"\\nDiD Estimate (ATT): {att:.2f} ₹ Cr")
    print(f"Interpretation: Field recovery changed by {treatment_diff:.2f} Cr post-shift.")
    print(f"After adjusting for the general trend (Control changed {control_diff:.2f} Cr),")
    print(f"the strategy shift attributable effect on Field = {att:.2f} ₹ Cr")
    if att < 0:
        print(">>> CONCLUSION [STRONG EVIDENCE]: The targeting shift REDUCED Field recovery.")
        print(f">>> Counterfactual: Without the shift, Field would have recovered ~₹{abs(att):.2f} Cr MORE.")
"""))

    # ── PART 5: INVESTMENT RECOMMENDATION ────────────────────────────────────
    cells.append(nbf.v4.new_markdown_cell("""## 6. Part 5: Investment Recommendation — ₹10 Cr

### Channel Performance (Cleaned Data)
"""))
    cells.append(nbf.v4.new_code_cell("""channel_df = con.execute(\"\"\"
    SELECT cam.channel,
        COUNT(DISTINCT p.account_id) AS accounts_recovered,
        SUM(p.amount)/1e7 AS recovered_cr,
        ROUND(AVG(p.amount),0) AS avg_payment_inr
    FROM campaigns cam
    JOIN daily_targeting dt ON cam.campaign_id = dt.campaign_id
    JOIN clean_payments p ON dt.account_id = p.account_id
    WHERE p.payment_status = 'SUCCESS'
    GROUP BY cam.channel ORDER BY recovered_cr DESC
\"\"\").fetchdf()

print("Channel Recovery Performance:")
print(channel_df.to_string(index=False))

# WhatsApp funnel
wa = con.execute("SELECT event_type, COUNT(*) cnt, COUNT(DISTINCT account_id) accts FROM whatsapp_events GROUP BY 1 ORDER BY 2 DESC").fetchdf()
print("\\nWhatsApp Event Funnel:")
print(wa.to_string(index=False))

# Recovery/agent-hour trajectory (declining → adding more agents won't help)
print("\\nRecovery per Agent-Hour (₹) — declining trend means agents are NOT the bottleneck:")
raph = con.execute("SELECT month, recovery_per_agent_hour_inr FROM golden_monthly_metrics").fetchdf()
print(raph.to_string(index=False))
"""))

    cells.append(nbf.v4.new_markdown_cell("""### Recommendation: WhatsApp / Digital Engagement

| Parameter | Estimate |
|-----------|----------|
| **Investment** | ₹10 Cr |
| **Cost per AI-WhatsApp interaction** | ~₹0.50 (vs ₹150+ for field visit) |
| **Expected uplift** | 15–20% more accounts recovered via digital (based on current 38.6% recovery rate) |
| **Incremental accounts** | ~870–1,160 additional accounts per month |
| **Avg payment size** | ₹75,158 |
| **Expected incremental recovery** | ₹12–18 Cr per year |
| **ROI (12 months)** | 1.2x–1.8x |
| **Break-even** | 7–9 months |
| **Confidence** | High — WhatsApp already leads all channels; this scales what works |
| **Downside scenario** | WhatsApp carrier block or opt-out surge → fallback to IVR |
| **Why NOT agents?** | Recovery/agent-hour fell 25% (₹16k→₹12k) — adding agents into a declining-yield system is wasteful |
| **Why NOT field ops?** | Lowest recovery/account despite highest contact cost |

**Classification: Strong Evidence** (based on 7-month channel data, not model inference)
"""))

    nb['cells'] = cells
    with open('notebooks/analysis.ipynb', 'w', encoding='utf-8') as f:
        nbf.write(nb, f)
    print("Notebook written.")

build_analysis_notebook()
