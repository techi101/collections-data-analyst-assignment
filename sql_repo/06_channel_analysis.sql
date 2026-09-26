-- ============================================================
-- 06_channel_analysis.sql
-- Which contact channel is associated with recovery?
--
-- The first version joined campaigns -> daily_targeting -> payments on
-- account_id with no time window, so one payment was counted once for every
-- campaign that ever targeted its account (channel totals summed to more
-- than total recovery). This version uses two honest views:
--
--  A. Last-touch attribution: each real payment is credited to the most
--     recent successful contact in the 30 days before it (WhatsApp delivered/
--     read/replied/clicked, SMS delivered/clicked, answered call, field
--     visit). No contact in 30 days = no-contact (self-cure). Every payment
--     is counted exactly once.
--  B. Lift: for accounts first reached by a channel, the share that paid
--     within 30 days, compared with the share of ALL accounts that pay in
--     any 30-day window. Attribution (A) rewards volume; lift (B) asks
--     whether contact changed behaviour.
-- ============================================================

DROP TABLE IF EXISTS stg_touches;
CREATE TABLE stg_touches AS
SELECT account_id, event_at, 'WHATSAPP' AS channel FROM whatsapp_events
    WHERE event_type IN ('DELIVERED', 'READ', 'REPLIED', 'PAYMENT_CLICK')
UNION ALL
SELECT account_id, event_at, 'SMS' FROM sms_events
    WHERE event_type IN ('DELIVERED', 'CLICKED')
UNION ALL
SELECT account_id, event_at_utc, 'VOICE' FROM stg_calls
    WHERE call_status = 'ANSWERED'
UNION ALL
SELECT account_id, event_at, 'FIELD' FROM field_visits;

DROP TABLE IF EXISTS channel_attribution;
CREATE TABLE channel_attribution AS
WITH pay AS (
    SELECT * FROM stg_recovery
    WHERE event_at >= DATE '2026-01-01' AND event_at < DATE '2026-08-01'
),
last_touch AS (
    SELECT p.payment_id, p.amount,
           ARG_MAX(t.channel, t.event_at) AS channel
    FROM pay p
    LEFT JOIN stg_touches t
      ON t.account_id = p.account_id
     AND t.event_at <  p.event_at
     AND t.event_at >= p.event_at - INTERVAL 30 DAY
    GROUP BY p.payment_id, p.amount
)
SELECT COALESCE(channel, 'NO_CONTACT_30D') AS channel,
       COUNT(*) AS payments,
       ROUND(SUM(amount) / 1e7, 2) AS recovered_cr,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_of_payments_pct
FROM last_touch
GROUP BY 1
ORDER BY recovered_cr DESC;

DROP TABLE IF EXISTS channel_lift;
CREATE TABLE channel_lift AS
WITH first_touch AS (
    SELECT channel, account_id, MIN(event_at) AS first_at
    FROM stg_touches
    WHERE event_at >= DATE '2026-01-01' AND event_at < DATE '2026-07-01'
    GROUP BY 1, 2
),
paid_after AS (
    SELECT f.channel, f.account_id,
           MAX(CASE WHEN p.payment_id IS NOT NULL THEN 1 ELSE 0 END) AS paid_30d
    FROM first_touch f
    LEFT JOIN stg_recovery p
      ON p.account_id = f.account_id
     AND p.event_at > f.first_at
     AND p.event_at <= f.first_at + INTERVAL 30 DAY
    GROUP BY 1, 2
),
baseline AS (
    -- share of all accounts paying in a 30-day window, averaged over Jan-Jun
    SELECT AVG(rate) AS base FROM (
        SELECT m, COUNT(DISTINCT r.account_id) * 1.0 / (SELECT COUNT(*) FROM accounts) AS rate
        FROM (SELECT UNNEST(GENERATE_SERIES(DATE '2026-01-01', DATE '2026-06-01', INTERVAL 1 MONTH)) AS m) months
        LEFT JOIN stg_recovery r ON r.event_at >= months.m AND r.event_at < months.m + INTERVAL 30 DAY
        GROUP BY m
    )
)
SELECT pa.channel,
       COUNT(*) AS accounts_reached,
       ROUND(100.0 * AVG(pa.paid_30d), 2) AS paid_within_30d_pct,
       ROUND(100.0 * b.base, 2) AS baseline_any_30d_pct,
       ROUND(100.0 * (AVG(pa.paid_30d) - b.base), 2) AS lift_pp
FROM paid_after pa CROSS JOIN baseline b
GROUP BY pa.channel, b.base
ORDER BY pa.channel;

SELECT * FROM channel_attribution;
SELECT * FROM channel_lift;
