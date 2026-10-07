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

-- WHAT THIS FILE IS: the "monthly report card": one row per month (Jan-Jul 2026) with every headline number.
-- Like a school report card that puts marks from different subjects (payments, calls, promises, agent hours) on one
-- page, it builds each subject separately in a CTE and then lines them up side by side by month.
-- Real example (January row): recovery Rs 18.72 Cr from 2,464 payments by 2,374 accounts; paying-account rate
-- 2,374 / 30,000 = 7.91%; answer rate 20.0%; RPC rate 76.5%; PTP kept 24.1%; 11,163 agent-hours;
-- Rs 16,773 per agent-hour. July recovery is again Rs 18.72 Cr: flat, neither a decline nor a rising trend.
-- THE TRAP (August version): the paying rate divided paying accounts by the accounts in daily_targeting that month,
-- but only 462 of January's 2,374 paying accounts were in that list, so the top and the bottom of the fraction were
-- different people. Corrected: divide by the whole portfolio of 30,000 accounts (7.2% to 8.1% every month).
-- Overall flow: stg_recovery + accounts + stg_calls/stg_dispositions + promises_to_pay + agent_sessions
--   -> 5 CTEs -> joined on month -> golden_monthly_metrics (7 rows) -> run_pipeline.py adds the MoM % column.
--
-- Start clean: delete the table if an earlier run made it, then build it from the query below.
DROP TABLE IF EXISTS golden_monthly_metrics;
CREATE TABLE golden_monthly_metrics AS
-- CTE "recovery": money recovered per month.
WITH recovery AS (
    -- strftime(event_at, '%Y-%m') = the month as text, e.g. "2026-01". (DATE_TRUNC('month', event_at) is another way;
    -- it gives the first day of the month as a date instead of text.)
    SELECT strftime(event_at, '%Y-%m') AS month,
           -- SUM(amount) = total rupees; COUNT(*) = number of payments; COUNT(DISTINCT account_id) = number of different
           -- accounts that paid (one account can pay twice in a month: 2,464 payments but 2,374 accounts in January).
           SUM(amount) AS total_recovery_inr,
           COUNT(*) AS payments,
           COUNT(DISTINCT account_id) AS accounts_paying
    -- stg_recovery = SUCCESS payments, one row per payment_id (file 01).
    FROM stg_recovery
    -- DATE '2026-01-01' = a date value. Keep 1 Jan up to (not including) 1 Aug, i.e. January to July.
    -- August is left out because it has only 8 days of data.
    WHERE event_at >= DATE '2026-01-01' AND event_at < DATE '2026-08-01'
    -- GROUP BY 1 = one row per month.
    GROUP BY 1
),
-- CTE "portfolio": one number, the total accounts in the portfolio (30,000). It is the denominator (the bottom of
-- the fraction) of the paying-account rate.
portfolio AS (SELECT COUNT(*) AS accounts_in_portfolio FROM accounts),
-- CTE "calls_m": call activity per month, using the UTC time from file 03.
calls_m AS (
    SELECT strftime(c.event_at_utc, '%Y-%m') AS month,
           -- calls = every call row; answered = calls with status 'ANSWERED' (CASE gives 1 or 0, and SUM adds them up).
           COUNT(*) AS calls,
           SUM(CASE WHEN c.call_status = 'ANSWERED' THEN 1 ELSE 0 END) AS answered,
           -- COUNT(d.call_id) counts only the rows where a disposition was found: COUNT(column) skips NULLs, COUNT(*) does not.
           COUNT(d.call_id) AS dispositioned,
           -- rpc = dispositions with is_rpc TRUE; ptp_dispositions = dispositions coded PTP_MADE (both spellings, file 04).
           SUM(CASE WHEN d.is_rpc THEN 1 ELSE 0 END) AS rpc,
           SUM(CASE WHEN d.normalized_code = 'PTP_MADE' THEN 1 ELSE 0 END) AS ptp_dispositions
    -- "stg_calls c" gives the table a short nickname (alias) c, so its columns can be written c.call_status.
    FROM stg_calls c
    -- LEFT JOIN = keep EVERY row of the left table (calls) and attach the matching disposition if there is one; calls with
    -- no disposition get NULL in the d columns. (An INNER JOIN, written plain "JOIN", would drop those calls.)
    -- ON c.call_id = d.call_id is the matching rule. File 04 kept one disposition per call, so no call is doubled.
    LEFT JOIN stg_dispositions d ON c.call_id = d.call_id
    -- One row per month.
    GROUP BY 1
),
-- CTE "ptp_m": promises per month from the promises_to_pay table (a separate table from the call dispositions).
ptp_m AS (
    SELECT strftime(event_at, '%Y-%m') AS month,
           -- ptps_made = all promises; ptps_kept = promises with status 'KEPT'. January: 2,522 made.
           COUNT(*) AS ptps_made,
           SUM(CASE WHEN status = 'KEPT' THEN 1 ELSE 0 END) AS ptps_kept
    FROM promises_to_pay GROUP BY 1
),
-- CTE "hours_m": agent working hours per month from agent_sessions (one row = one login-to-logout session).
hours_m AS (
    SELECT strftime(login_at, '%Y-%m') AS month,
           -- logout_at - login_at = how long the session lasted. EXTRACT(EPOCH FROM ...) turns that length into seconds;
           -- / 3600.0 turns seconds into hours. SUM adds up all sessions of the month.
           SUM(EXTRACT(EPOCH FROM (logout_at - login_at))) / 3600.0 AS agent_hours
    -- Skip sessions with no logout time (NULL), since their length is unknown. (In this data none are missing.)
    FROM agent_sessions WHERE logout_at IS NOT NULL GROUP BY 1
)
-- Final SELECT: one row per month with every metric side by side.
SELECT
    r.month,
    -- ROUND(x, 2) = 2 decimals. / 1e7 turns rupees into crores (1 crore = 10,000,000): 187,229,127.59 -> 18.72.
    ROUND(r.total_recovery_inr, 2) AS total_recovery_inr,
    ROUND(r.total_recovery_inr / 1e7, 2) AS total_recovery_cr,
    r.payments,
    r.accounts_paying,
    -- Paying-account rate = accounts that paid * 100.0 / 30,000. Writing 100.0 (not 100) makes sure the result is a
    -- decimal number; in some databases whole-number division throws away the decimals.
    ROUND(r.accounts_paying * 100.0 / p.accounts_in_portfolio, 2) AS paying_account_rate_pct,
    -- NULLIF(x, 0) = NULL if x is 0, else x. Dividing by NULL gives NULL instead of a divide-by-zero error.
    -- Answer rate = answered / calls; RPC rate = rpc / dispositioned calls.
    ROUND(cm.answered * 100.0 / NULLIF(cm.calls, 0), 1) AS answer_rate_pct,
    ROUND(cm.rpc * 100.0 / NULLIF(cm.dispositioned, 0), 1) AS rpc_rate_pct,
    cm.ptp_dispositions,
    pm.ptps_made,
    -- PTP kept rate = kept promises / all promises (24.1% in January).
    ROUND(pm.ptps_kept * 100.0 / NULLIF(pm.ptps_made, 0), 1) AS ptp_kept_rate_pct,
    -- Agent hours, rounded to whole hours, and recovery per agent-hour (rupees / hours): Rs 16,117-17,008 every month.
    ROUND(h.agent_hours) AS agent_hours,
    ROUND(r.total_recovery_inr / NULLIF(h.agent_hours, 0)) AS recovery_per_agent_hour_inr
-- Start from the recovery CTE (7 months) and attach the others.
FROM recovery r
-- CROSS JOIN = pair every row on the left with every row on the right. portfolio has exactly 1 row, so this just
-- adds the 30,000 onto every month row.
CROSS JOIN portfolio p
-- LEFT JOINs on month: keep all 7 recovery months and attach the calls, promises and hours of the same month.
-- If a month had no calls, its call columns would be NULL instead of the whole month disappearing.
LEFT JOIN calls_m cm ON r.month = cm.month
LEFT JOIN ptp_m  pm ON r.month = pm.month
LEFT JOIN hours_m h ON r.month = h.month
-- Sort the months in time order.
ORDER BY r.month;

-- Audit query (result not saved): show the finished table.
SELECT * FROM golden_monthly_metrics;
