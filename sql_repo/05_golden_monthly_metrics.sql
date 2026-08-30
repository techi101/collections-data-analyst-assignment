-- ============================================================
-- 05_golden_monthly_metrics.sql
-- The core analytical layer for leadership reporting
-- Source-of-truth monthly metrics from the clean Golden Dataset
-- 
-- METRIC DEFINITIONS (independent, reproducible):
--
-- Recovery Rate = Unique accounts with SUCCESS payment / All active accounts in portfolio
--   Why: Counts distinct accounts, not payment events (avoids double-counting)
--
-- Contact Rate = Calls with RPC disposition / Total unique call attempts per account
--   Why: Uses normalized dispositions; includes legacy 'PROMISE_TO_PAY' codes
--
-- PTP Rate = Unique accounts with PTP_MADE disposition / Accounts that were contacted (RPC=TRUE)
--   Why: Only meaningful relative to contacted accounts, not total portfolio
--
-- PTP Kept Rate = PTPs with status='KEPT' / Total PTPs made in that month
--   Why: Measures follow-through quality
--
-- Recovery per Agent-Hour = Total recovered / Total agent-hours logged in sessions
--   Why: Captures true labor productivity
--
-- ============================================================

DROP TABLE IF EXISTS golden_monthly_metrics;
CREATE TABLE golden_monthly_metrics AS
WITH months AS (
    SELECT DISTINCT strftime(event_at, '%Y-%m') AS month 
    FROM clean_payments 
    WHERE payment_status = 'SUCCESS'
      AND strftime(event_at, '%Y-%m') != '2026-08'  -- Exclude partial month
),
-- 1. Recovery
recovery AS (
    SELECT 
        strftime(event_at, '%Y-%m') AS month,
        SUM(amount) AS total_recovery_inr,
        COUNT(DISTINCT account_id) AS accounts_recovered,
        COUNT(*) AS payment_events
    FROM clean_payments
    WHERE payment_status = 'SUCCESS'
      AND strftime(event_at, '%Y-%m') != '2026-08'
    GROUP BY 1
),
-- 2. Active portfolio denominator (all accounts visible in any targeting that month)
active_accounts AS (
    SELECT 
        strftime(target_date, '%Y-%m') AS month,
        COUNT(DISTINCT account_id) AS active_accounts_in_portfolio
    FROM daily_targeting
    WHERE strftime(target_date, '%Y-%m') != '2026-08'
    GROUP BY 1
),
-- 3. Call metrics with normalized dispositions
call_metrics AS (
    SELECT
        strftime(c.event_at, '%Y-%m') AS month,
        COUNT(DISTINCT c.account_id) AS accounts_attempted,
        COUNT(DISTINCT CASE WHEN d.is_rpc THEN c.account_id END) AS accounts_contacted_rpc,
        COUNT(DISTINCT CASE WHEN d.normalized_code = 'PTP_MADE' THEN c.account_id END) AS accounts_with_ptp,
        SUM(c.duration_sec) / 3600.0 AS total_call_hours
    FROM calls c
    LEFT JOIN stg_dispositions d ON c.call_id = d.call_id
    WHERE strftime(c.event_at, '%Y-%m') != '2026-08'
    GROUP BY 1
),
-- 4. Agent hours from sessions
agent_hours AS (
    SELECT
        strftime(login_at, '%Y-%m') AS month,
        SUM(
            EXTRACT(EPOCH FROM (logout_at - login_at)) / 3600.0
        ) AS agent_hours_logged
    FROM agent_sessions
    WHERE logout_at IS NOT NULL
      AND strftime(login_at, '%Y-%m') != '2026-08'
    GROUP BY 1
),
-- 5. PTP kept rate
ptp_metrics AS (
    SELECT
        strftime(event_at, '%Y-%m') AS month,
        COUNT(*) AS ptps_made,
        SUM(CASE WHEN status = 'KEPT' THEN 1 ELSE 0 END) AS ptps_kept,
        SUM(promised_amount) AS total_promised
    FROM promises_to_pay
    WHERE strftime(event_at, '%Y-%m') != '2026-08'
    GROUP BY 1
)
SELECT
    r.month,
    r.total_recovery_inr,
    r.total_recovery_inr / 1e7 AS total_recovery_cr,
    r.accounts_recovered,
    a.active_accounts_in_portfolio,
    -- RECOVERY RATE (our independent definition)
    ROUND(r.accounts_recovered * 100.0 / NULLIF(a.active_accounts_in_portfolio, 0), 2) AS recovery_rate_pct,
    -- CONTACT RATE
    ROUND(cm.accounts_contacted_rpc * 100.0 / NULLIF(cm.accounts_attempted, 0), 2) AS contact_rate_rpc_pct,
    -- PTP RATE (of contacted)
    ROUND(cm.accounts_with_ptp * 100.0 / NULLIF(cm.accounts_contacted_rpc, 0), 2) AS ptp_rate_pct,
    -- PTP KEPT RATE
    ROUND(pm.ptps_kept * 100.0 / NULLIF(pm.ptps_made, 0), 2) AS ptp_kept_rate_pct,
    -- RECOVERY PER ACCOUNT
    ROUND(r.total_recovery_inr / NULLIF(r.accounts_recovered, 0), 0) AS recovery_per_account_inr,
    -- RECOVERY PER AGENT HOUR
    ROUND(r.total_recovery_inr / NULLIF(ah.agent_hours_logged, 0), 0) AS recovery_per_agent_hour_inr,
    cm.total_call_hours,
    ah.agent_hours_logged,
    pm.ptps_made,
    pm.ptps_kept
FROM recovery r
LEFT JOIN active_accounts a   ON r.month = a.month
LEFT JOIN call_metrics cm     ON r.month = cm.month
LEFT JOIN agent_hours ah      ON r.month = ah.month
LEFT JOIN ptp_metrics pm      ON r.month = pm.month
ORDER BY r.month;
