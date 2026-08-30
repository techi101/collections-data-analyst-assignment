-- ============================================================
-- 03_staging_calls.sql
-- Normalize call timestamps to UTC
-- Fix timezone issues: UTC, Asia/Kolkata (+05:30), Asia/Dubai (+04:00)
-- Tag duplicate calls (same account+timestamp)
-- ============================================================

DROP TABLE IF EXISTS stg_calls;
CREATE TABLE stg_calls AS
WITH tz_normalized AS (
    SELECT *,
        CASE 
            WHEN timezone = 'Asia/Kolkata' THEN 
                event_at - INTERVAL '5 hours 30 minutes'
            WHEN timezone = 'Asia/Dubai' THEN 
                event_at - INTERVAL '4 hours'
            ELSE event_at  -- already UTC
        END AS event_at_utc,
        -- IST hour for business-hours analysis
        CASE 
            WHEN timezone = 'UTC' THEN 
                CAST(strftime(event_at + INTERVAL '5 hours 30 minutes', '%H') AS INT)
            WHEN timezone = 'Asia/Dubai' THEN 
                CAST(strftime(event_at + INTERVAL '1 hours 30 minutes', '%H') AS INT)
            ELSE 
                CAST(strftime(event_at, '%H') AS INT)
        END AS hour_ist
    FROM calls
),
deduped AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY account_id, event_at 
            ORDER BY call_id
        ) AS rn
    FROM tz_normalized
)
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
    CASE WHEN rn > 1 THEN TRUE ELSE FALSE END AS is_duplicate
FROM deduped;

-- How many calls were cross-timezone errors?
SELECT 
    timezone,
    COUNT(*) as total_calls,
    SUM(CASE WHEN is_duplicate THEN 1 ELSE 0 END) as duplicates
FROM stg_calls
GROUP BY timezone;
