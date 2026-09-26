-- ============================================================
-- 07_statistical_investigation.sql
-- Part 3: Mix effects, Simpson's Paradox, Survivorship Bias
-- ============================================================

-- 1. MIX EFFECT: Has the DPD bucket composition changed month-on-month?
-- If we are suddenly recovering more easy (low DPD) accounts, 
-- recovery rate goes up but is NOT an operational improvement.
SELECT
    strftime(p.event_at, '%Y-%m') AS month,
    a.dpd,
    COUNT(DISTINCT p.account_id) AS recovered_accounts,
    SUM(p.amount) / 1e7 AS recovered_cr
FROM stg_recovery p
JOIN accounts a ON p.account_id = a.account_id
WHERE p.payment_status = 'SUCCESS'
  AND strftime(p.event_at, '%Y-%m') != '2026-08'
GROUP BY 1, 2
ORDER BY 1, 2;

-- 2. SIMPSON'S PARADOX CHECK: Within each DPD bucket, is recovery improving?
WITH bucket_monthly AS (
    SELECT
        strftime(p.event_at, '%Y-%m') AS month,
        CASE 
            WHEN a.dpd <= 30  THEN 'Early (0-30 DPD)'
            WHEN a.dpd <= 90  THEN 'Mid (31-90 DPD)'
            ELSE                   'Late (91+ DPD)'
        END AS dpd_bucket,
        SUM(p.amount) AS recovered
    FROM stg_recovery p
    JOIN accounts a ON p.account_id = a.account_id
    WHERE p.payment_status = 'SUCCESS'
      AND strftime(p.event_at, '%Y-%m') != '2026-08'
    GROUP BY 1, 2
)
SELECT 
    month,
    dpd_bucket,
    recovered / 1e7 AS recovered_cr,
    LAG(recovered) OVER (PARTITION BY dpd_bucket ORDER BY month) AS prev_month,
    ROUND(
        (recovered - LAG(recovered) OVER (PARTITION BY dpd_bucket ORDER BY month)) 
        / LAG(recovered) OVER (PARTITION BY dpd_bucket ORDER BY month) * 100, 2
    ) AS mom_growth_within_bucket
FROM bucket_monthly
ORDER BY month, dpd_bucket;

-- 3. SURVIVORSHIP BIAS: Are accounts that never received a call excluded from conversion denominators?
SELECT
    CASE 
        WHEN c.account_id IS NOT NULL THEN 'Has call history'
        ELSE 'Never called (potentially excluded)'
    END AS contact_status,
    COUNT(DISTINCT a.account_id) AS accounts,
    COUNT(DISTINCT p.account_id) AS accounts_recovered,
    ROUND(COUNT(DISTINCT p.account_id) * 100.0 / COUNT(DISTINCT a.account_id), 2) AS recovery_rate_pct
FROM accounts a
LEFT JOIN (SELECT DISTINCT account_id FROM calls) c ON a.account_id = c.account_id
LEFT JOIN stg_recovery p ON a.account_id = p.account_id AND p.payment_status = 'SUCCESS'
GROUP BY 1;

-- 4. AGENT TENURE ANALYSIS: removed.
-- The first version joined agents on agent_name, but the agents table has
-- only 10 names for 1,000 agent_ids and each id's employee_code, name and
-- joined_at change row to row (see 02_staging_agents.sql). Tenure cannot be
-- measured reliably from this master data, so no tenure claim is made.
