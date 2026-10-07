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

-- WHAT THIS FILE IS: the "translator" for call outcome codes. After each call the agent picks a disposition (an
-- outcome code). The code list changed over time (schema versions legacy, v1 and v2), and one outcome ended up with
-- two spellings: PTP and PROMISE_TO_PAY both mean "the borrower promised to pay". Like counting votes where some
-- ballots say "Yes" and others say "Y", you must merge both spellings before counting.
-- Real example: the raw call_dispositions table has 3,904 PTP rows and 3,926 PROMISE_TO_PAY rows (7,830 promises).
-- THE TRAP: counting only 'PTP' misses the 3,926 PROMISE_TO_PAY rows, about 50% of all promises. (The August version
-- said "a third"; in fact both codes appear in all 3 versions.)
-- The table also has 35,000 rows for only 28,971 calls, so this file keeps ONE disposition per call (the earliest).
-- After that, 6,509 calls are PTP_MADE.
-- Overall flow: call_dispositions (raw) -> keep the earliest row per call_id -> normalized_code (PTP and
--   PROMISE_TO_PAY become PTP_MADE) + is_rpc flag -> stg_dispositions (28,971 rows) -> audit count per code.
--
-- Start clean: delete stg_dispositions if an earlier run made it, then build it from the query below.
DROP TABLE IF EXISTS stg_dispositions;
CREATE TABLE stg_dispositions AS
-- CTE "one_per_call": one row per call_id.
WITH one_per_call AS (
    -- A SUBQUERY = a query inside brackets that is used like a table. The inner query numbers each call's
    -- dispositions; the outer "SELECT * FROM ( ... ) WHERE rn = 1" keeps only the first one.
    SELECT * FROM (
        -- ROW_NUMBER() per call_id, earliest event_at first; disposition_id breaks a tie when two rows have the same time.
        SELECT *, ROW_NUMBER() OVER (PARTITION BY call_id ORDER BY event_at, disposition_id) AS rn
        FROM call_dispositions
    -- Keep only the earliest disposition of each call (rn = 1): 35,000 rows become 28,971.
    ) WHERE rn = 1
)
-- Final SELECT: the disposition columns to keep, plus two new ones below.
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
    -- This CASE maps every raw code to one standard name. IN ('PROMISE_TO_PAY', 'PTP') = "equal to any value in the
    -- list". Both promise spellings become 'PTP_MADE'. The other codes keep their own name, and ELSE keeps any
    -- unexpected code as it is, so nothing silently disappears.
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
    -- is_rpc (Right Party Contact) = TRUE when the call reached the actual borrower and they engaged: they promised,
    -- paid, disputed, refused, broke a promise or asked for a callback. NO_CONTACT and WRONG_NUMBER give FALSE.
    -- Real result: 22,357 of the 28,971 kept dispositions are RPC. File 05 turns this into the monthly RPC rate
    -- (76.2% to 78.5%).
    CASE 
        WHEN disposition_code IN ('PROMISE_TO_PAY', 'PTP', 'PAID', 'DISPUTE', 'REFUSED', 'PTP_BROKEN', 'CALLBACK') 
        THEN TRUE ELSE FALSE 
    END AS is_rpc
-- Read from the CTE.
FROM one_per_call;

-- Verify unified PTP count
-- Audit query (result not saved): rows per normalized code, biggest first (ORDER BY 2 DESC = sort by the 2nd
-- column, descending). Real result: PTP_MADE 6,509 at the top; every other code has about 3,100-3,300 rows.
SELECT normalized_code, COUNT(*) as cnt FROM stg_dispositions GROUP BY 1 ORDER BY 2 DESC;
