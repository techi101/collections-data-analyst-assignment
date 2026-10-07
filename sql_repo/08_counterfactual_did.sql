-- ============================================================
-- 08_counterfactual_did.sql
-- Difference-in-differences: did the April 2026 strategy shift change the
-- payment rate of accounts targeted by FIELD campaigns?
--
-- Unit: one targeting row (account, campaign, target_date).
-- Outcome: did the account make a SUCCESS payment within 30 days AFTER the
--   target date? (The first version joined every payment the account ever
--   made, before or after targeting, and never computed the estimate.)
-- Treatment: FIELD campaigns. Control: WhatsApp + SMS campaigns.
-- Pre: target_date before 2026-04-01. Post: 2026-04-01 to 2026-06-30
--   (so every post row has a full 30-day window inside the data).
-- DiD = (Field post - Field pre) - (Digital post - Digital pre)
-- Assumption to check: parallel pre-trends (the pre rates are shown).
-- ============================================================

-- WHAT THIS FILE IS: a "before and after, with a comparison group" test of the April 2026 strategy shift.
-- Analogy: a school starts extra coaching for one class in April. Their marks change, but the marks of the other
-- classes (no coaching) also moved for other reasons. Difference-in-differences (DiD) = (change in the coached class)
-- minus (change in the other classes), so the ups and downs that hit everyone cancel out.
-- Here the "coached class" (treatment) = accounts targeted by FIELD campaigns; the comparison group (control) =
-- accounts targeted by WhatsApp + SMS campaigns. PRE = targeted Jan-Mar, POST = targeted Apr-Jun.
-- Real example: Field went 7.22% -> 8.20% (+0.98 pp); digital went 7.68% -> 7.32% (-0.36 pp);
-- DiD = 0.98 - (-0.36) = +1.34 pp. run_pipeline.py adds the 95% confidence interval: -0.25 to +2.93 pp.
-- A confidence interval = the range the true value probably lies in. This one includes 0, so the data cannot rule
-- out "no effect": no detectable effect.
-- THE TRAP (August version): it joined every payment the account EVER made (even before targeting) and never
-- computed the estimate, yet claimed the shift "reduced Field recovery".
-- Key assumption (parallel trends): without the shift, both groups would have moved the same way. The PRE rates
-- (7.22% vs 7.68%) are shown so this can be judged.
-- Overall flow: daily_targeting + campaigns -> one row per targeting event with group + period
--   -> did the account pay within 30 days after the target date? -> % per group and period -> did_results (4 rows)
--   -> the DiD estimate.
--
-- Start clean: delete did_results if an earlier run made it, then build it from the query below.
DROP TABLE IF EXISTS did_results;
CREATE TABLE did_results AS
-- CTE "t": one row per targeting row (account, campaign, target_date), labelled with its group and period.
WITH t AS (
    SELECT dt.account_id, dt.target_date,
           -- grp: FIELD campaigns -> 'TREATMENT_FIELD'; WhatsApp or SMS -> 'CONTROL_DIGITAL'. (There is no ELSE, so any other
           -- channel would get NULL, but the WHERE below already keeps only these three channels.)
           CASE WHEN cam.channel = 'FIELD' THEN 'TREATMENT_FIELD'
                WHEN cam.channel IN ('WHATSAPP', 'SMS') THEN 'CONTROL_DIGITAL' END AS grp,
           -- period: target date before 1 April -> 'PRE', otherwise 'POST'.
           CASE WHEN dt.target_date < DATE '2026-04-01' THEN 'PRE' ELSE 'POST' END AS period
    -- daily_targeting = which account each campaign targeted on which day (45,000 rows). JOIN campaigns brings in each
    -- campaign's channel; JOIN (an INNER JOIN) keeps only targeting rows whose campaign_id is found in campaigns.
    FROM daily_targeting dt
    JOIN campaigns cam ON cam.campaign_id = dt.campaign_id
    -- Keep FIELD, WHATSAPP and SMS campaigns only (VOICE and MIXED campaigns are left out), and target dates from 1 Jan
    -- to 30 Jun, so every POST row has a full 30-day window inside the data.
    WHERE cam.channel IN ('FIELD', 'WHATSAPP', 'SMS')
      AND dt.target_date >= DATE '2026-01-01' AND dt.target_date < DATE '2026-07-01'
),
-- CTE "o" (outcome): paid_30d = 1 if the account made a SUCCESS payment in the 30 days after the target date, else 0.
o AS (
    SELECT t.grp, t.period, t.account_id, t.target_date,
           -- MAX(CASE ...) = 1 if at least one payment matched.
           MAX(CASE WHEN p.payment_id IS NOT NULL THEN 1 ELSE 0 END) AS paid_30d
    FROM t
    -- LEFT JOIN keeps targeting rows with no payment (they get 0). Match: same account, payment after the target date
    -- and no later than target_date + 30 days. This time window is what the August version was missing.
    LEFT JOIN stg_recovery p
      ON p.account_id = t.account_id
     AND p.event_at >  t.target_date
     AND p.event_at <= t.target_date + INTERVAL 30 DAY
    -- GROUP BY the 4 columns = back to one row per (group, period, account, target date).
    GROUP BY 1, 2, 3, 4
)
-- Per group and period: number of rows and the % that paid within 30 days.
-- Real result: CONTROL_DIGITAL PRE 8,984 rows 7.68%, POST 9,116 rows 7.32%; TREATMENT_FIELD PRE 2,783 rows 7.22%,
-- POST 2,816 rows 8.20%.
SELECT grp, period, COUNT(*) AS targeting_rows, ROUND(100.0 * AVG(paid_30d), 2) AS paid_within_30d_pct
-- ORDER BY 1, 2 DESC = sort by group, then by period in reverse alphabetical order (PRE before POST).
FROM o GROUP BY 1, 2 ORDER BY 1, 2 DESC;

-- Audit query (result not saved): show the 4 rows.
SELECT * FROM did_results;

-- The DiD estimate as one number. Each MAX(CASE WHEN grp = ... AND period = ... THEN pct END) picks out one of the
-- 4 percentages (CASE gives NULL on the other 3 rows, and MAX ignores NULLs).
-- (Field POST - Field PRE) - (Digital POST - Digital PRE) = (8.20 - 7.22) - (7.32 - 7.68) = 1.34 pp.
-- This result is not saved here either; run_pipeline.py repeats the same calculation and stores it.
SELECT
    ROUND( (MAX(CASE WHEN grp='TREATMENT_FIELD' AND period='POST' THEN paid_within_30d_pct END)
          - MAX(CASE WHEN grp='TREATMENT_FIELD' AND period='PRE'  THEN paid_within_30d_pct END))
         - (MAX(CASE WHEN grp='CONTROL_DIGITAL' AND period='POST' THEN paid_within_30d_pct END)
          - MAX(CASE WHEN grp='CONTROL_DIGITAL' AND period='PRE'  THEN paid_within_30d_pct END)), 2) AS did_estimate_pp
FROM did_results;
