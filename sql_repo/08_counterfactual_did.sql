-- ============================================================
-- 08_counterfactual_did.sql
-- Part 4: Difference-in-Differences Counterfactual
-- "What would recovery look like if we had NOT changed targeting strategy?"
--
-- Strategy shift assumed at: 2026-04-01 (midway, April)
-- (Campaigns table shows strategy_version shift from 'legacy'/'v1' to 'v2'/'v3' ~April)
-- Treatment group: Accounts pushed to Field after the shift
-- Control group:   Accounts remaining on Digital (WhatsApp/SMS) throughout
--
-- Assumptions:
--   1. Parallel trends: pre-April, Field and Digital recovery moved together
--   2. No spillover: a Field visit doesn't affect Digital conversion
--   3. The mix of DPD within groups was constant pre-shift (to be verified)
--
-- DiD estimate = (Treatment_Post - Treatment_Pre) - (Control_Post - Control_Pre)
-- ============================================================

WITH campaign_groups AS (
    SELECT 
        cam.campaign_id,
        cam.channel,
        cam.strategy_version,
        CASE 
            WHEN cam.start_at < DATE '2026-04-01' THEN 'PRE_SHIFT'
            ELSE 'POST_SHIFT'
        END AS period,
        CASE 
            WHEN cam.channel = 'FIELD' THEN 'TREATMENT'
            WHEN cam.channel IN ('WHATSAPP', 'SMS') THEN 'CONTROL'
            ELSE 'OTHER'
        END AS group_label
    FROM campaigns cam
),
recovery_by_group AS (
    SELECT
        cg.group_label,
        cg.period,
        COUNT(DISTINCT p.account_id) AS accounts_recovered,
        SUM(p.amount) AS total_recovery
    FROM campaign_groups cg
    JOIN daily_targeting dt ON cg.campaign_id = dt.campaign_id
    LEFT JOIN clean_payments p ON dt.account_id = p.account_id AND p.payment_status = 'SUCCESS'
    WHERE cg.group_label IN ('TREATMENT', 'CONTROL')
    GROUP BY 1, 2
)
SELECT
    group_label,
    period,
    accounts_recovered,
    total_recovery / 1e7 AS recovery_cr
FROM recovery_by_group
ORDER BY group_label, period;

-- DiD point estimate (manual calculation narrative):
-- ATT (Average Treatment Effect on Treated) =
--   [Field POST - Field PRE] - [Digital POST - Digital PRE]
-- If ATT < 0, the strategy shift HURT Field recovery performance
-- This is the counterfactual: without the shift, Field would have recovered ATT more

-- Confounding factors:
--   - DPD mix shifted to harder accounts for Field post-shift (attenuates estimate)
--   - Seasonal effects (Q1 vs Q2 collections cycles)
--   - Vendor changes coinciding with strategy shift (Airtel inactive → Knowlarity)
