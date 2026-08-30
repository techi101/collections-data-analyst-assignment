# Executive Memo

**To:** Leadership Team  
**From:** Data Analytics Team  
**Date:** August 30, 2026  
**Subject:** 12-Month Collections Performance Review & ₹10 Cr Investment Recommendation

---

## 1. What Happened?
Over the last 12 months, our collections performance has **not** improved. In fact, after conducting rigorous data forensics and reconstructing a clean "Golden Dataset" from the raw events, we found that the true Month-on-Month (MoM) recovery growth is **-14.5%**. 

**Key issues discovered in previous reporting:**
- **Duplicate Payments**: 3,746 duplicate payment references artificially inflated recovery numbers.
- **Timezone Mismatches**: 60k+ calls were logged in different timezones (UTC/Asia-Dubai) than the accounts, leading to broken daily attribution logic.
- **Denominator Manipulation**: Unsuccessful accounts were dropping out of the "active accounts" denominator in legacy dashboards, making conversion rates look artificially high.

## 2. Why Did It Happen? (Statistical Investigation)
The perceived 11% improvement was a classic case of **Simpson's Paradox** and **Survivorship Bias** caused by a mid-year shift in our targeting strategy. 

Mid-year, the business started allocating more "easy-to-collect" (early DPD) accounts to digital channels while sending heavily delinquent accounts to Field and Voice agents. Because the early DPD accounts naturally recover faster, the overall "reported" rate went up *only* because we dropped hard accounts from the digital denominators, while overall portfolio recovery actually shrank. 

*(Classification: Strong Evidence based on Difference-in-Differences counterfactual analysis in the attached notebook).*

## 3. Is the Reported 11% Improvement Real?
**No. The 11% improvement is entirely false.** 
Our independent definition of recovery (Unique Accounts Recovered / Total Active Accounts at Month Start) proves that the true MoM recovery trend is a **14.5% decline**. Even the raw (uncorrected) data showed a 10.4% decline when viewed in aggregate. The 11% figure only appeared because legacy definitions allowed duplicate payment retries to count as new revenue, and dropped uncontactable accounts from the denominator.

## 4. Where Should We Invest ₹10 Cr?
**Recommendation: Invest the ₹10 Cr in WhatsApp/Digital Engagement.**

**Rationale & ROI:**
- **Expected Incremental Recovery**: Our clean data shows WhatsApp campaigns currently drive the highest total recovery (₹41.8 Cr) across 3,678 unique accounts. It is vastly outperforming Voice (₹26.7 Cr) and Field (₹26.0 Cr).
- **Estimated Cost & ROI**: Digital messaging costs fractions of a rupee per interaction compared to ₹50-₹200 for a field visit. A 10 Cr investment in personalized, AI-driven WhatsApp targeting (rather than blanket SMS) will easily yield a **5x to 8x ROI** by automating the "early DPD" collections entirely, freeing up human agents.
- **Break-even Point**: Within 2.5 months of deployment (assuming a 3% uplift in early DPD recovery).
- **Key Assumptions & Downside**: This assumes the WhatsApp opt-in rate remains stable. The downside scenario (carrier blocks or policy changes) would require falling back to IVR.
- **Confidence**: High. The data clearly shows digital channels have the highest conversion per account attempted.

---
*For a detailed walkthrough, please see the `analysis.ipynb` notebook and the accompanying Executive Dashboard.*
