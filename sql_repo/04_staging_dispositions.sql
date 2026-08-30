-- ============================================================
-- 04_staging_dispositions.sql
-- Normalize disposition codes across schema versions:
--   legacy: PROMISE_TO_PAY  -> canonical: PTP_MADE
--   v1/v2:  PTP             -> canonical: PTP_MADE
--   legacy: PAID            -> canonical: PAID
--   v1/v2:  PAID            -> canonical: PAID
-- Classification: CONTACTED if disposition is not NO_CONTACT or WRONG_NUMBER
-- ============================================================

DROP TABLE IF EXISTS stg_dispositions;
CREATE TABLE stg_dispositions AS
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
FROM call_dispositions;

-- Verify unified PTP count
SELECT normalized_code, COUNT(*) as cnt FROM stg_dispositions GROUP BY 1 ORDER BY 2 DESC;
