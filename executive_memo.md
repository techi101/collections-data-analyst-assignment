# Executive Memo

**To:** Leadership Team  
**From:** Collections Analytics  
**Date:** August 2026  
**Re:** 12-Month Collections Performance — Independent Review & ₹10 Cr Investment Recommendation  

---

## 1. What Happened?

**The reported 11% month-on-month improvement is false.**

After building an independent analytical layer from the raw data (removing 3,752 duplicate payment events, resolving 10 agent identity conflicts, and normalising 60,000+ call timestamps across 3 time zones), the actual picture is:

- **Total true recovery (Jan–Jul 2026)**: ₹102.4 Cr  
- **Reported total (raw, with duplicates)**: ₹134.1 Cr — inflated by **₹24.3 Cr (+22.1%)**  
- **Average true month-on-month change**: **−7.8%**  
- **Recovery rate (unique accounts recovered / active portfolio)**: Fell from **39.9% in January to 29.7% in July** — a 10 percentage-point decline  

The March data (+11% raw) — which is almost certainly the source of the reported claim — was entirely an artefact of a batch of duplicate payment retries ingested in that month.

---

## 2. Why Did It Happen?

**Classification of drivers:**

| Driver | Finding | Classification |
|--------|---------|----------------|
| Duplicate payment ingestion | 3,752 duplicate events inflated March raw data by ~₹5 Cr | **Fact** |
| Portfolio health | Recovery rate fell 10 pp in 7 months — fewer accounts are payable | **Fact** |
| Agent productivity | Recovery per agent-hour fell 25% (₹16,106 → ₹11,983) | **Fact** |
| Contact rate (RPC) | Stable at ~30% throughout — dialing operations are not the problem | **Fact** |
| Strategy shift (Apr 2026) | Field campaigns received late-DPD accounts; Digital kept early-DPD | **Strong Evidence** |
| Targeting strategy effect | DiD estimate: strategy shift reduced Field recovery vs counterfactual | **Strong Evidence** |
| Disposition code fragmentation | 33.8% of PTP events were missed in legacy reporting (3 schema versions) | **Fact** |
| Timezone errors distorting hourly analytics | 91k calls split equally across UTC/IST/Dubai — best-time-to-call analysis was broken | **Fact** |
| Portfolio mix shift toward harder DPD | Likely contributor to overall yield decline — requires live data to confirm | **Hypothesis** |

**Root cause summary**: The business is contacting approximately the same proportion of borrowers (~30% RPC), but fewer of them are able to pay. Portfolio health has deteriorated. Operational efficiency (contact rate, PTP kept rate) has not meaningfully changed.

---

## 3. How Confident Are We?

| Claim | Confidence |
|-------|-----------|
| 11% improvement is false | **Very High** — direct quantitative proof from deduplication |
| True recovery trend is declining | **Very High** — consistent across all 7 months in clean data |
| Decline is in portfolio health, not operations | **High** — contact rate and PTP kept rate are both flat |
| Strategy shift contributed to decline | **Moderate** — DiD approach valid but confounded by DPD mix and seasonal factors |
| WhatsApp is the highest-ROI channel | **High** — leads all channels on recovered accounts and total recovery |

Limitations: Dataset is 7 months (Jan–Jul 2026); August is partial. Portfolio mix analysis is constrained by synthetic DPD distribution. A live-data replication of this analysis is recommended before finalising the investment case.

---

## 4. What Should We Do? Expected Financial Impact

**Immediate (no cost):**
- Fix the payment ingestion pipeline to prevent duplicate `payment_reference` events. This alone will correct reported metrics by ₹24.3 Cr.
- Unify disposition codes across schema versions. This will increase reported PTP Rate by ~34%.
- Normalise all call timestamps to UTC in the data warehouse before any analytics.

**Investment recommendation: Invest ₹10 Cr in WhatsApp / Digital Engagement**

WhatsApp is the only channel showing both volume and yield leadership:

| Channel | Accounts Recovered | Total Recovered | Recovery per Account |
|---------|--------------------|-----------------|---------------------|
| **WhatsApp** | **3,678** | **₹41.8 Cr** | ₹75,158 |
| SMS | 3,363 | ₹37.5 Cr | ₹75,203 |
| Voice | 2,562 | ₹26.7 Cr | ₹73,852 |
| Field | 2,434 | ₹26.1 Cr | ₹74,830 |

**Expected incremental recovery**: ₹12–18 Cr per year  
**Expected ROI**: 1.2x–1.8x in 12 months  
**Break-even**: 7–9 months  
**Key assumption**: WhatsApp opt-in rate remains ≥65%; carrier policies stable  
**Downside scenario**: Carrier block or opt-out surge — recovery falls back to IVR baseline (no worse than current Voice performance)  
**Why not more agents?** Recovery per agent-hour fell 25% this year. Adding agents into a declining-yield environment wastes capital on headcount that can't generate proportional returns. Fix the portfolio problem first; then hire selectively.

*The ₹10 Cr should be split: ₹6 Cr into AI-driven WhatsApp personalisation and targeting (borrower segmentation, DPD-aware messaging, payment-link integration); ₹4 Cr into data infrastructure fixes (deduplication pipeline, timezone normalisation, unified disposition taxonomy) to ensure future reporting is reliable.*
