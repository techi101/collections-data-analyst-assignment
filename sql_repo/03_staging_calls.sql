-- ============================================================
-- 03_staging_calls.sql
-- Normalize call timestamps to UTC
-- Fix timezone issues: UTC, Asia/Kolkata (+05:30), Asia/Dubai (+04:00)
-- Tag duplicate calls (same account+timestamp)
-- ============================================================

-- WHAT THIS FILE IS: the "world clock" fix for calls. Imagine three call centres writing call times by their own
-- wall clocks (India, Dubai and UTC) into one register: "10:00" then means three different moments. This file turns
-- every time into UTC (Coordinated Universal Time = one shared world clock), so calls can be compared with each
-- other and with payments.
-- Real example: CALL0000002 for ACC0002025 is stored as 2026-06-10 06:48:27 with timezone 'Asia/Kolkata'
-- (India, UTC+5:30), so its UTC time is 2026-06-10 01:18:27. The raw calls table is split almost evenly:
-- 30,485 Asia/Kolkata, 30,464 Asia/Dubai and 30,401 UTC calls (91,350 in all).
-- It also FLAGS (does not delete) possible duplicate calls: same account at the exact same stored time.
-- Real result: 1,339 calls get is_duplicate = TRUE.
-- Overall flow: calls (raw, local times) -> add event_at_utc + hour_ist -> number calls sharing account + time
--   -> stg_calls (all 91,350 rows, with is_duplicate) -> audit counts per timezone.
--
-- Start clean: delete stg_calls if an earlier run made it, then build it from the query below.
DROP TABLE IF EXISTS stg_calls;
CREATE TABLE stg_calls AS
-- CTE 1 "tz_normalized": every raw call row plus two new columns, event_at_utc and hour_ist.
WITH tz_normalized AS (
    SELECT *,
        -- This CASE builds event_at_utc. INTERVAL '5 hours 30 minutes' = a length of time that can be added to or
        -- taken away from a timestamp. India is 5:30 AHEAD of UTC, so UTC = India time - 5:30.
        CASE 
            WHEN timezone = 'Asia/Kolkata' THEN 
                event_at - INTERVAL '5 hours 30 minutes'
            -- Dubai is 4 hours ahead of UTC, so UTC = Dubai time - 4:00.
            WHEN timezone = 'Asia/Dubai' THEN 
                event_at - INTERVAL '4 hours'
            -- Everything else (the 'UTC' rows) is already UTC and is copied unchanged.
            ELSE event_at  -- already UTC
        END AS event_at_utc,
        -- IST hour for business-hours analysis
        -- Second CASE: the hour of the day in Indian time (0-23), for "business hours in India" questions.
        -- strftime(ts, '%H') = the hour as 2-digit text ("06"); CAST(... AS INT) turns that text into the number 6.
        -- UTC time + 5:30 = India time.
        CASE 
            WHEN timezone = 'UTC' THEN 
                CAST(strftime(event_at + INTERVAL '5 hours 30 minutes', '%H') AS INT)
            -- Dubai time + 1:30 = India time (India is 5:30 ahead of UTC, Dubai 4:00 ahead, so the gap is 1:30).
            WHEN timezone = 'Asia/Dubai' THEN 
                CAST(strftime(event_at + INTERVAL '1 hours 30 minutes', '%H') AS INT)
            -- Asia/Kolkata rows are already in India time, so just take their hour.
            ELSE 
                CAST(strftime(event_at, '%H') AS INT)
        END AS hour_ist
    -- Read the raw calls table.
    FROM calls
),
-- CTE 2 "deduped": number the calls that share the same account_id AND the exact same stored event_at
-- (the stored local time, not the UTC time).
deduped AS (
    SELECT *,
        -- Window function ROW_NUMBER(): inside each (account_id, event_at) group, number the rows 1, 2, ... in call_id order.
        -- A group with one call gets rn 1. Two calls for one account at the same moment get rn 1 and rn 2 (the 2nd is suspect).
        ROW_NUMBER() OVER (
            PARTITION BY account_id, event_at 
            ORDER BY call_id
        ) AS rn
    -- Read from CTE 1, so the new time columns come along.
    FROM tz_normalized
)
-- Final SELECT: the call columns to keep, both times (original event_at and event_at_utc), hour_ist and timezone.
SELECT 
    call_id,
    account_id,
    borrower_id,
    event_at,
    event_at_utc,
    hour_ist,
    agent_id,
    campaign_id,
    direction,
    vendor_id,
    call_status,
    duration_sec,
    timezone,
    -- is_duplicate = TRUE for every copy after the first (rn > 1). Rows are only FLAGGED; none are removed, and
    -- files 05 and 06 read stg_calls without filtering on this flag.
    CASE WHEN rn > 1 THEN TRUE ELSE FALSE END AS is_duplicate
-- Read from CTE 2.
FROM deduped;

-- How many calls were cross-timezone errors?
-- Audit query (result not saved): per timezone, total calls and how many are flagged as duplicates.
-- Real result: Asia/Dubai 30,464 (464 flagged), Asia/Kolkata 30,485 (444), UTC 30,401 (431).
SELECT 
    timezone,
    COUNT(*) as total_calls,
    -- SUM(CASE WHEN is_duplicate THEN 1 ELSE 0 END) = the number of TRUE rows.
    SUM(CASE WHEN is_duplicate THEN 1 ELSE 0 END) as duplicates
FROM stg_calls
-- GROUP BY timezone = one output row per timezone value.
GROUP BY timezone;
