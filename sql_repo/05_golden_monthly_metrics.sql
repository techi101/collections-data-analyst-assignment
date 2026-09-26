-- ============================================================
-- 05_golden_monthly_metrics.sql
-- Source-of-truth monthly metrics, Jan-Jul 2026 (August is partial: 8 days).
--
-- METRIC DEFINITIONS
--   Recovery (INR)         = SUM(amount) of SUCCESS payments, one row per payment_id
--   Paying-account rate    = distinct accounts with a SUCCESS payment in the month
--                            / all 30,000 accounts in the portfolio
--     (The first version divided by the 5,732 accounts in daily_targeting in
--      January, but only 462 of January's 2,374 paying accounts were in that
--      group, so numerator and denominator did not describe the same people.)
--   Answer rate            = calls with call_status = 'ANSWERED' / all calls
--   RPC rate               = right-party-contact dispositions / dispositioned calls
--   PTP made               = dispositions PTP or PROMISE_TO_PAY (all versions)
--   PTP kept rate          = promises_to_pay with status KEPT / all promises made
--   Recovery per agent-hour = recovery / hours logged in agent_sessions
-- ============================================================

DROP TABLE IF EXISTS golden_monthly_metrics;
CREATE TABLE golden_monthly_metrics AS
WITH recovery AS (
    SELECT strftime(event_at, '%Y-%m') AS month,
           SUM(amount) AS total_recovery_inr,
           COUNT(*) AS payments,
           COUNT(DISTINCT account_id) AS accounts_paying
    FROM stg_recovery
    WHERE event_at >= DATE '2026-01-01' AND event_at < DATE '2026-08-01'
    GROUP BY 1
),
portfolio AS (SELECT COUNT(*) AS accounts_in_portfolio FROM accounts),
calls_m AS (
    SELECT strftime(c.event_at_utc, '%Y-%m') AS month,
           COUNT(*) AS calls,
           SUM(CASE WHEN c.call_status = 'ANSWERED' THEN 1 ELSE 0 END) AS answered,
           COUNT(d.call_id) AS dispositioned,
           SUM(CASE WHEN d.is_rpc THEN 1 ELSE 0 END) AS rpc,
           SUM(CASE WHEN d.normalized_code = 'PTP_MADE' THEN 1 ELSE 0 END) AS ptp_dispositions
    FROM stg_calls c
    LEFT JOIN stg_dispositions d ON c.call_id = d.call_id
    GROUP BY 1
),
ptp_m AS (
    SELECT strftime(event_at, '%Y-%m') AS month,
           COUNT(*) AS ptps_made,
           SUM(CASE WHEN status = 'KEPT' THEN 1 ELSE 0 END) AS ptps_kept
    FROM promises_to_pay GROUP BY 1
),
hours_m AS (
    SELECT strftime(login_at, '%Y-%m') AS month,
           SUM(EXTRACT(EPOCH FROM (logout_at - login_at))) / 3600.0 AS agent_hours
    FROM agent_sessions WHERE logout_at IS NOT NULL GROUP BY 1
)
SELECT
    r.month,
    r.total_recovery_inr,
    ROUND(r.total_recovery_inr / 1e7, 2) AS total_recovery_cr,
    r.payments,
    r.accounts_paying,
    ROUND(r.accounts_paying * 100.0 / p.accounts_in_portfolio, 2) AS paying_account_rate_pct,
    ROUND(cm.answered * 100.0 / NULLIF(cm.calls, 0), 1) AS answer_rate_pct,
    ROUND(cm.rpc * 100.0 / NULLIF(cm.dispositioned, 0), 1) AS rpc_rate_pct,
    cm.ptp_dispositions,
    pm.ptps_made,
    ROUND(pm.ptps_kept * 100.0 / NULLIF(pm.ptps_made, 0), 1) AS ptp_kept_rate_pct,
    ROUND(h.agent_hours) AS agent_hours,
    ROUND(r.total_recovery_inr / NULLIF(h.agent_hours, 0)) AS recovery_per_agent_hour_inr
FROM recovery r
CROSS JOIN portfolio p
LEFT JOIN calls_m cm ON r.month = cm.month
LEFT JOIN ptp_m  pm ON r.month = pm.month
LEFT JOIN hours_m h ON r.month = h.month
ORDER BY r.month;

SELECT * FROM golden_monthly_metrics;
