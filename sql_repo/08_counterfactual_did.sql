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

DROP TABLE IF EXISTS did_results;
CREATE TABLE did_results AS
WITH t AS (
    SELECT dt.account_id, dt.target_date,
           CASE WHEN cam.channel = 'FIELD' THEN 'TREATMENT_FIELD'
                WHEN cam.channel IN ('WHATSAPP', 'SMS') THEN 'CONTROL_DIGITAL' END AS grp,
           CASE WHEN dt.target_date < DATE '2026-04-01' THEN 'PRE' ELSE 'POST' END AS period
    FROM daily_targeting dt
    JOIN campaigns cam ON cam.campaign_id = dt.campaign_id
    WHERE cam.channel IN ('FIELD', 'WHATSAPP', 'SMS')
      AND dt.target_date >= DATE '2026-01-01' AND dt.target_date < DATE '2026-07-01'
),
o AS (
    SELECT t.grp, t.period, t.account_id, t.target_date,
           MAX(CASE WHEN p.payment_id IS NOT NULL THEN 1 ELSE 0 END) AS paid_30d
    FROM t
    LEFT JOIN stg_recovery p
      ON p.account_id = t.account_id
     AND p.event_at >  t.target_date
     AND p.event_at <= t.target_date + INTERVAL 30 DAY
    GROUP BY 1, 2, 3, 4
)
SELECT grp, period, COUNT(*) AS targeting_rows, ROUND(100.0 * AVG(paid_30d), 2) AS paid_within_30d_pct
FROM o GROUP BY 1, 2 ORDER BY 1, 2 DESC;

SELECT * FROM did_results;

SELECT
    ROUND( (MAX(CASE WHEN grp='TREATMENT_FIELD' AND period='POST' THEN paid_within_30d_pct END)
          - MAX(CASE WHEN grp='TREATMENT_FIELD' AND period='PRE'  THEN paid_within_30d_pct END))
         - (MAX(CASE WHEN grp='CONTROL_DIGITAL' AND period='POST' THEN paid_within_30d_pct END)
          - MAX(CASE WHEN grp='CONTROL_DIGITAL' AND period='PRE'  THEN paid_within_30d_pct END)), 2) AS did_estimate_pp
FROM did_results;
