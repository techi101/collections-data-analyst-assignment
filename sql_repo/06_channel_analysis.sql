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

-- WHAT THIS FILE IS: the "who gets the credit?" file for contact channels (WhatsApp, SMS, voice calls, field visits).
-- Analogy: a goal in football. Last-touch attribution gives the goal to the last player who touched the ball.
-- Lift asks a different question: does the team score MORE often when this player is on the pitch? A player who
-- touches the ball a lot collects many "last touches" without making any difference to the score.
-- Real example: last-touch gives WhatsApp the most credit, Rs 16.95 Cr from 2,252 payments, only because it sends the
-- most messages (40,242 WhatsApp touches). But 10,793 of the 16,918 Jan-Jul payments (63.8%, Rs 80.84 Cr) had NO
-- contact in the 30 days before. And lift: accounts reached by WhatsApp paid within 30 days at 7.77% against a 7.7%
-- baseline for all accounts (+0.07 pp). Every channel's lift is between +0.07 and +0.27 pp, and every 95% interval
-- includes 0 (run_pipeline.py adds the intervals). So the data cannot pick a winning channel.
-- THE TRAP (August version): joining campaigns to payments on account_id with NO time window counted one payment
-- once for every campaign that ever targeted the account, so channel totals added up to more than total recovery.
-- Overall flow: 4 contact tables -> stg_touches (one row per successful contact)
--   -> A. channel_attribution (each Jan-Jul payment -> its last touch in the prior 30 days, or NO_CONTACT_30D)
--   -> B. channel_lift (accounts first reached Jan-Jun -> paid within 30 days? compared with an all-account baseline).
--
-- Start clean: delete stg_touches if an earlier run made it, then build it from the stacked SELECTs below.
DROP TABLE IF EXISTS stg_touches;
CREATE TABLE stg_touches AS
-- WhatsApp touches: message events that show the borrower was actually reached (delivered, read, replied, clicked
-- the payment link). 'WHATSAPP' AS channel = a fixed text label put on every row.
SELECT account_id, event_at, 'WHATSAPP' AS channel FROM whatsapp_events
    WHERE event_type IN ('DELIVERED', 'READ', 'REPLIED', 'PAYMENT_CLICK')
-- UNION ALL = stack the next SELECT's rows under the previous ones, keeping every row. (Plain UNION would also remove
-- identical rows.) The column names come from the first SELECT: account_id, event_at, channel.
UNION ALL
-- SMS touches: delivered or clicked.
SELECT account_id, event_at, 'SMS' FROM sms_events
    WHERE event_type IN ('DELIVERED', 'CLICKED')
UNION ALL
-- Voice touches: answered calls only, with the UTC time from file 03 (it lands in the event_at column).
SELECT account_id, event_at_utc, 'VOICE' FROM stg_calls
    WHERE call_status = 'ANSWERED'
UNION ALL
-- Field touches: every field visit row (an agent visiting the borrower in person).
-- Real result: stg_touches has 40,242 WhatsApp, 22,358 SMS, 18,146 voice and 25,000 field rows.
SELECT account_id, event_at, 'FIELD' FROM field_visits;

-- ===== A. LAST-TOUCH ATTRIBUTION =====
-- Start clean, then build channel_attribution: one row per channel with its payments and money.
DROP TABLE IF EXISTS channel_attribution;
CREATE TABLE channel_attribution AS
-- CTE "pay": successful payments of January to July (16,918 payments).
WITH pay AS (
    SELECT * FROM stg_recovery
    WHERE event_at >= DATE '2026-01-01' AND event_at < DATE '2026-08-01'
),
-- CTE "last_touch": for each payment, the channel of the latest touch in the 30 days before it.
last_touch AS (
    SELECT p.payment_id, p.amount,
           -- ARG_MAX(channel, event_at) = "the channel value on the row with the biggest event_at", i.e. the latest touch.
           -- If a payment has no touch in the window, the LEFT JOIN gives only NULLs and ARG_MAX returns NULL.
           ARG_MAX(t.channel, t.event_at) AS channel
    FROM pay p
    -- LEFT JOIN keeps every payment, even one with no matching touch. The matching rule (ON ... AND ... AND ...):
    -- same account, touch strictly BEFORE the payment, and not more than 30 days before it (INTERVAL 30 DAY).
    -- This 30-day time window is exactly what the August version was missing.
    LEFT JOIN stg_touches t
      ON t.account_id = p.account_id
     AND t.event_at <  p.event_at
     AND t.event_at >= p.event_at - INTERVAL 30 DAY
    -- GROUP BY payment_id, amount = squash each payment's matching touches back into ONE row per payment,
    -- so every payment is counted exactly once.
    GROUP BY p.payment_id, p.amount
)
-- COALESCE(a, b) = the first value that is not NULL. A NULL channel (no touch) becomes 'NO_CONTACT_30D'.
SELECT COALESCE(channel, 'NO_CONTACT_30D') AS channel,
       -- Per channel: the number of payments and the money in crores.
       COUNT(*) AS payments,
       ROUND(SUM(amount) / 1e7, 2) AS recovered_cr,
       -- Share of payments. SUM(COUNT(*)) OVER () is a window over ALL groups (an empty OVER () = the whole result), so it
       -- is the grand total, 16,918. Example: 10,793 / 16,918 = 63.8% for NO_CONTACT_30D.
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_of_payments_pct
FROM last_touch
-- One row per channel, biggest money first.
-- Real result: NO_CONTACT_30D Rs 80.84 Cr, WHATSAPP 16.95, FIELD 10.93, SMS 9.94, VOICE 8.19.
GROUP BY 1
ORDER BY recovered_cr DESC;

-- ===== B. LIFT =====
-- Lift = (share of reached accounts that paid within 30 days) - (baseline share of ALL accounts that pay in any
-- 30-day window), in percentage points (pp). A lift near 0 means contact did not change behaviour.
-- Start clean, then build channel_lift.
DROP TABLE IF EXISTS channel_lift;
CREATE TABLE channel_lift AS
-- CTE "first_touch": for each channel and account, the FIRST touch time (MIN = the earliest) between 1 Jan and
-- 30 Jun. Stopping before 1 July leaves every account a full 30 days of data after its first touch.
WITH first_touch AS (
    SELECT channel, account_id, MIN(event_at) AS first_at
    FROM stg_touches
    WHERE event_at >= DATE '2026-01-01' AND event_at < DATE '2026-07-01'
    -- GROUP BY 1, 2 = one row per (channel, account_id).
    GROUP BY 1, 2
),
-- CTE "paid_after": did that account make a successful payment in the 30 days AFTER its first touch?
paid_after AS (
    SELECT f.channel, f.account_id,
           -- MAX(CASE WHEN a payment matched THEN 1 ELSE 0 END) = 1 if at least one payment matched, else 0.
           MAX(CASE WHEN p.payment_id IS NOT NULL THEN 1 ELSE 0 END) AS paid_30d
    FROM first_touch f
    -- LEFT JOIN keeps accounts that never paid (they get 0). Match: same account, payment after first_at and
    -- no later than first_at + 30 days.
    LEFT JOIN stg_recovery p
      ON p.account_id = f.account_id
     AND p.event_at > f.first_at
     AND p.event_at <= f.first_at + INTERVAL 30 DAY
    -- Back to one row per (channel, account_id), even if the account paid several times.
    GROUP BY 1, 2
),
-- CTE "baseline": the normal paying rate with no channel filter at all.
baseline AS (
    -- share of all accounts paying in a 30-day window, averaged over Jan-Jun
    -- Outer query: AVG(rate) = the average of the 6 rates below (real result: 7.7%).
    SELECT AVG(rate) AS base FROM (
        -- For each start date m: different accounts that paid in the 30 days from m, divided by all accounts.
        -- (SELECT COUNT(*) FROM accounts) is a scalar subquery = a query that returns one single value (30,000).
        -- * 1.0 makes sure the division gives a decimal.
        SELECT m, COUNT(DISTINCT r.account_id) * 1.0 / (SELECT COUNT(*) FROM accounts) AS rate
        -- GENERATE_SERIES(start, end, step) makes a LIST of dates: 1 Jan, 1 Feb, ..., 1 Jun (6 dates, 1 month apart).
        -- UNNEST turns that list into 6 separate rows, in a column m of a mini-table named "months".
        FROM (SELECT UNNEST(GENERATE_SERIES(DATE '2026-01-01', DATE '2026-06-01', INTERVAL 1 MONTH)) AS m) months
        -- LEFT JOIN so a start date with no payments would still appear (with a count of 0).
        LEFT JOIN stg_recovery r ON r.event_at >= months.m AND r.event_at < months.m + INTERVAL 30 DAY
        -- One rate per start date.
        GROUP BY m
    )
)
-- Final SELECT per channel: accounts reached, % that paid within 30 days, the baseline %, and the lift in pp.
-- AVG(paid_30d) of 1s and 0s = the share that paid.
SELECT pa.channel,
       COUNT(*) AS accounts_reached,
       ROUND(100.0 * AVG(pa.paid_30d), 2) AS paid_within_30d_pct,
       ROUND(100.0 * b.base, 2) AS baseline_any_30d_pct,
       ROUND(100.0 * (AVG(pa.paid_30d) - b.base), 2) AS lift_pp
-- CROSS JOIN baseline puts the single baseline number onto every row.
FROM paid_after pa CROSS JOIN baseline b
-- b.base must be in GROUP BY because it is selected without being summed or averaged (it is one value anyway).
-- Real result: FIELD 14,827 reached, 7.92% (+0.23 pp); SMS 7.91% (+0.21); VOICE 7.96% (+0.27);
-- WHATSAPP 19,876 reached, 7.77% (+0.07). This is a comparison, not an experiment: who gets contacted is not random,
-- which is why the corrected recommendation is a randomised holdout test before spending Rs 10 Cr.
GROUP BY pa.channel, b.base
ORDER BY pa.channel;

-- Audit queries (results not saved): show both finished tables.
SELECT * FROM channel_attribution;
SELECT * FROM channel_lift;
