-- ============================================================
-- 07_statistical_investigation.sql
-- Part 3: Mix effects, Simpson's Paradox, Survivorship Bias
-- ============================================================

-- WHAT THIS FILE IS: three "is the headline fooling us?" checks. Like asking whether a class average rose because
-- students improved or because the weak students simply left, these queries look for hidden causes behind a number.
-- Real example: in January, accounts at dpd 0 paid Rs 1.83 Cr (226 accounts); inside the Early (0-30 DPD) bucket
-- recovery fell 12.92% in February and rose 21.62% in March; never-called accounts paid at 43.22% against 44.34%
-- for called accounts.
-- Important: none of these 3 queries creates a table. run_pipeline.py runs them and throws the results away; they are
-- for running by hand. The portfolio-mix numbers in the report come from Check F in run_pipeline.py.
-- Overall flow: stg_recovery + accounts (+ calls) -> 1. recovery per month per dpd value
--   -> 2. recovery per month per DPD bucket with month-on-month growth -> 3. paying share of called vs never-called.
-- (Section 4, agent tenure, was removed: see the note at the end.)
--
-- DPD = days past due: how many days late the borrower is. The accounts table has 11 different dpd values from 0 to
-- 180, one value per account (a snapshot), not the value on the payment date.
-- 1. MIX EFFECT: Has the DPD bucket composition changed month-on-month?
-- If we are suddenly recovering more easy (low DPD) accounts, 
-- recovery rate goes up but is NOT an operational improvement.
-- Query 1 (MIX EFFECT): a mix effect = the overall number moves because the MIX of easy and hard cases changed, not
-- because anyone worked better. One output row per (month, dpd value).
SELECT
    strftime(p.event_at, '%Y-%m') AS month,
    a.dpd,
    -- recovered_accounts = different accounts that paid; recovered_cr = money in crores (SUM / 1e7).
    COUNT(DISTINCT p.account_id) AS recovered_accounts,
    SUM(p.amount) / 1e7 AS recovered_cr
-- JOIN (an INNER JOIN) keeps only payments that have a matching account row, and brings in that account's dpd.
FROM stg_recovery p
JOIN accounts a ON p.account_id = a.account_id
-- stg_recovery already holds only SUCCESS rows, so this status test changes nothing; it is a harmless repeat.
-- != '2026-08' = "not equal to": leave out the partial month of August.
WHERE p.payment_status = 'SUCCESS'
  AND strftime(p.event_at, '%Y-%m') != '2026-08'
-- GROUP BY 1, 2 = one group per (month, dpd); ORDER BY 1, 2 = sort by month, then by dpd.
-- Real result: 77 rows (7 months x 11 dpd values).
GROUP BY 1, 2
ORDER BY 1, 2;

-- 2. SIMPSON'S PARADOX CHECK: Within each DPD bucket, is recovery improving?
-- Query 2 (SIMPSON'S PARADOX): Simpson's paradox = a trend in the total can vanish or even reverse inside every
-- subgroup (or the other way round), because the sizes of the subgroups changed.
-- CTE "bucket_monthly": recovery per month per DPD bucket.
WITH bucket_monthly AS (
    SELECT
        strftime(p.event_at, '%Y-%m') AS month,
        -- CASE puts each dpd into one of 3 buckets. The WHEN tests run top to bottom and the first true one wins,
        -- so "dpd <= 90" only catches 31-90 (0-30 were already caught by the line before).
        CASE 
            WHEN a.dpd <= 30  THEN 'Early (0-30 DPD)'
            WHEN a.dpd <= 90  THEN 'Mid (31-90 DPD)'
            ELSE                   'Late (91+ DPD)'
        END AS dpd_bucket,
        -- recovered = total rupees in that month and bucket.
        SUM(p.amount) AS recovered
    FROM stg_recovery p
    JOIN accounts a ON p.account_id = a.account_id
    -- Same filters as query 1: SUCCESS (already true) and not August.
    WHERE p.payment_status = 'SUCCESS'
      AND strftime(p.event_at, '%Y-%m') != '2026-08'
    GROUP BY 1, 2
)
-- Main query: recovery per bucket and its month-on-month growth.
SELECT 
    month,
    dpd_bucket,
    recovered / 1e7 AS recovered_cr,
    -- LAG(x) OVER (PARTITION BY dpd_bucket ORDER BY month) = a window function that reads x from the PREVIOUS row of
    -- the same bucket, in month order. January has no previous row, so LAG gives NULL there.
    -- prev_month is in rupees (not crores), e.g. 84,514,560.18 for the Early bucket in January.
    LAG(recovered) OVER (PARTITION BY dpd_bucket ORDER BY month) AS prev_month,
    -- Growth % = (this month - last month) / last month * 100, rounded to 2 decimals.
    -- Real result: Early bucket -12.92% in February, then +21.62% in March; Late bucket -5.37%, then +0.66%.
    ROUND(
        (recovered - LAG(recovered) OVER (PARTITION BY dpd_bucket ORDER BY month)) 
        / LAG(recovered) OVER (PARTITION BY dpd_bucket ORDER BY month) * 100, 2
    ) AS mom_growth_within_bucket
-- Sort by month, then by bucket name (alphabetical: Early, Late, Mid).
FROM bucket_monthly
ORDER BY month, dpd_bucket;

-- 3. SURVIVORSHIP BIAS: Are accounts that never received a call excluded from conversion denominators?
-- Query 3 (SURVIVORSHIP BIAS): survivorship bias = judging only the cases that "survived" a filter (here, accounts
-- that were called) and forgetting the ones filtered out. This compares called and never-called accounts.
SELECT
    -- CASE: an account found in the list of called accounts -> 'Has call history', otherwise 'Never called ...'.
    CASE 
        WHEN c.account_id IS NOT NULL THEN 'Has call history'
        ELSE 'Never called (potentially excluded)'
    END AS contact_status,
    -- accounts = all accounts in the group; accounts_recovered = those with a SUCCESS payment (any month, August too,
    -- because stg_recovery has no date filter); recovery_rate_pct = the second divided by the first.
    COUNT(DISTINCT a.account_id) AS accounts,
    COUNT(DISTINCT p.account_id) AS accounts_recovered,
    ROUND(COUNT(DISTINCT p.account_id) * 100.0 / COUNT(DISTINCT a.account_id), 2) AS recovery_rate_pct
-- Start from ALL 30,000 accounts.
FROM accounts a
-- LEFT JOIN to the list of accounts that were ever called (SELECT DISTINCT = each account once).
-- No match -> c.account_id is NULL -> 'Never called'.
LEFT JOIN (SELECT DISTINCT account_id FROM calls) c ON a.account_id = c.account_id
-- LEFT JOIN to successful payments. An account with several payments appears on several rows, but
-- COUNT(DISTINCT ...) above still counts it once.
LEFT JOIN stg_recovery p ON a.account_id = p.account_id AND p.payment_status = 'SUCCESS'
-- One row per contact_status.
-- Real result: 28,408 called accounts, 44.34% paid; 1,592 never-called accounts, 43.22% paid. Nearly the same,
-- in line with file 06, where contact shows no measurable lift.
GROUP BY 1;

-- 4. AGENT TENURE ANALYSIS: removed.
-- The first version joined agents on agent_name, but the agents table has
-- only 10 names for 1,000 agent_ids and each id's employee_code, name and
-- joined_at change row to row (see 02_staging_agents.sql). Tenure cannot be
-- measured reliably from this master data, so no tenure claim is made.
