-- ============================================================
-- 04_staging_dispositions.sql
-- Normalize disposition codes across schema versions:
--   legacy: PROMISE_TO_PAY  -> canonical: PTP_MADE
--   v1/v2:  PTP             -> canonical: PTP_MADE
--   legacy: PAID            -> canonical: PAID
--   v1/v2:  PAID            -> canonical: PAID
-- Classification: CONTACTED if disposition is not NO_CONTACT or WRONG_NUMBER
--
-- Both PTP codes appear in ALL three versions (legacy, v1, v2) across the
-- whole period, so a report counting only 'PTP' misses PROMISE_TO_PAY:
-- 3,926 of 7,830 promise dispositions (50%), not "a third".
-- The raw table has 35,000 rows for 28,971 call_ids; one disposition per
-- call is kept (the earliest).
-- ============================================================

DROP TABLE IF EXISTS stg_dispositions;
CREATE TABLE stg_dispositions AS
WITH one_per_call AS (
    SELECT * FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY call_id ORDER BY event_at, disposition_id) AS rn
        FROM call_dispositions
    ) WHERE rn = 1
)
SELECT
    disposition_id,
    account_id,
    borrower_id,
    event_at,
    call_id,
    agent_id,
    disposition_code,
    disposition_version,
    -- Normalized code
    CASE 
        WHEN disposition_code IN ('PROMISE_TO_PAY', 'PTP') THEN 'PTP_MADE'
        WHEN disposition_code = 'PTP_BROKEN'               THEN 'PTP_BROKEN'
        WHEN disposition_code = 'PAID'                     THEN 'PAID'
        WHEN disposition_code = 'CALLBACK'                 THEN 'CALLBACK'
        WHEN disposition_code = 'DISPUTE'                  THEN 'DISPUTE'
        WHEN disposition_code = 'REFUSED'                  THEN 'REFUSED'
        WHEN disposition_code = 'NO_CONTACT'               THEN 'NO_CONTACT'
        WHEN disposition_code = 'WRONG_NUMBER'             THEN 'WRONG_NUMBER'
        ELSE disposition_code
    END AS normalized_code,
    -- Right Party Contact: got through to actual borrower and they engaged
    CASE 
        WHEN disposition_code IN ('PROMISE_TO_PAY', 'PTP', 'PAID', 'DISPUTE', 'REFUSED', 'PTP_BROKEN', 'CALLBACK') 
        THEN TRUE ELSE FALSE 
    END AS is_rpc
FROM one_per_call;

-- Verify unified PTP count
SELECT normalized_code, COUNT(*) as cnt FROM stg_dispositions GROUP BY 1 ORDER BY 2 DESC;
