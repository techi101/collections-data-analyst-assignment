-- ============================================================
-- 01_staging_payments.sql
-- One row per real payment.
--
-- Dedup key: payment_id (keep the earliest row).
--   payment_id repeats 500 times in the raw file (486 exact copies,
--   14 copies that differ only in reference/method/provider).
--
-- NOT a dedup key: payment_reference.
--   3,407 references appear more than once, and in every one of those
--   groups the rows belong to DIFFERENT accounts with DIFFERENT amounts.
--   They are separate payments whose reference numbers collide.
--   The first version of this file deduplicated on payment_reference and
--   deleted 2,703 real successful payments worth Rs 20.4 Cr (Jan-Jul): 4% of
--   January's recovery rising to 28.5% of July's, because the longer the
--   data runs, the more references collide. That manufactured a false
--   "decline". See CORRECTIONS.md.
--
-- Status is filtered AFTER dedup of payment_id only; REVERSED payments do
-- not match any earlier SUCCESS (same account and amount), so they are
-- kept as their own events and simply excluded from recovery.
-- ============================================================

-- WHAT THIS FILE IS: the "cleaning desk" for payments. Like a bank clerk who throws away photocopies of the same
-- cheque but keeps every genuine cheque, it keeps ONE row per payment_id and drops the repeated copies.
-- Real example: the raw payments table has 25,500 rows but only 25,000 different payment_id values, so 500 rows
-- are copies (486 exact copies, 14 that differ only in reference/method/provider). After this file stg_payments
-- has 25,000 rows: 17,534 SUCCESS, 3,677 FAILED, 2,535 PENDING, 1,254 REVERSED. Recovery built on it is
-- Rs 18.72 Cr in January and again Rs 18.72 Cr in July (flat).
-- THE TRAP (August version): it deduplicated on payment_reference instead. But one reference number can belong to
-- DIFFERENT accounts: TXN0000062541 is used by ACC0005143 (Rs 96,247.47) and by ACC0019406 (Rs 82,765.53).
-- Those are two real payments, not copies. Keeping one row per reference deleted 2,703 real successful payments
-- worth Rs 20.4 Cr (Jan-Jul), more each month, and invented a decline. Real duplicates (by payment_id) are only
-- 325 successful rows worth Rs 2.45 Cr in Jan-Jul, about 1.9%, spread evenly over the months.
-- Overall flow: payments (raw) -> number the copies of each payment_id -> keep copy no. 1 -> add a quality flag
--   -> stg_payments -> stg_recovery (SUCCESS + CLEAN rows only) -> audit totals per status.
--
-- DROP TABLE IF EXISTS = delete the table if an earlier run made it, so this run starts clean (no error if absent).
DROP TABLE IF EXISTS stg_payments;
-- CREATE TABLE name AS <query> = make a new, stored table filled with whatever the query returns.
CREATE TABLE stg_payments AS
-- WITH ranked AS ( ... ) is a CTE (Common Table Expression): a named helper result that exists only inside this
-- one statement, like a scratch sheet. The main SELECT further down reads from "ranked".
WITH ranked AS (
    -- SELECT * = take every column of the raw payments table, then add the two new columns below.
    SELECT *,
        -- A WINDOW FUNCTION = a calculation over a group ("window") of related rows that still keeps every row.
        -- (GROUP BY would squash each group into one row; a window does not.)
        -- OVER (PARTITION BY payment_id ...) = each window is all rows with the same payment_id.
        -- ROW_NUMBER() numbers the rows inside each window 1, 2, 3 ... in ORDER BY order: earliest event_at first, and
        -- payment_reference breaks a tie when two copies have the same time. So rn = 1 is the earliest copy.
        -- Example: PAYMENT0000001 appears once, so its only row gets rn = 1. A payment_id with 2 rows gets rn 1 and rn 2.
        ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY event_at, payment_reference) AS rn,
        -- COUNT(*) OVER (PARTITION BY payment_id) = how many rows share this payment_id, written onto every one of them.
        COUNT(*)     OVER (PARTITION BY payment_id) AS copies
    -- FROM payments = read the raw table loaded from payments.csv.
    FROM payments
)
-- Main SELECT: pick the payment columns to keep (rn and copies themselves are not kept).
SELECT
    payment_id, account_id, borrower_id, event_at, payment_reference,
    amount, payment_status, payment_method, provider_id,
    -- copies - 1 = how many extra copies of this payment were dropped (0 for most payments).
    -- "AS name" gives a new column its name (an alias).
    copies - 1 AS duplicate_rows_removed,
    -- CASE WHEN ... THEN ... ELSE ... END = SQL's if / else-if / else. The first WHEN that is true wins.
    -- Rule: amount 0 or below -> 'REJECTED_ZERO_AMOUNT'; no account_id -> 'REJECTED_NO_ACCOUNT'; otherwise 'CLEAN'.
    -- NULL = SQL's empty cell ("no value at all"). Test it with IS NULL, never with "= NULL" (that is never true).
    -- In this data all 25,000 rows come out 'CLEAN'; the flag is a safety net.
    CASE WHEN amount <= 0          THEN 'REJECTED_ZERO_AMOUNT'
         WHEN account_id IS NULL   THEN 'REJECTED_NO_ACCOUNT'
         ELSE 'CLEAN' END AS quality_flag
-- Read from the CTE built above.
FROM ranked
-- WHERE = keep only the rows that pass the test. rn = 1 keeps the earliest copy of each payment_id.
-- (Some databases have QUALIFY rn = 1 to filter on a window result directly; this file uses the plain WHERE form.)
-- payment_status is NOT filtered here, so the dedup looks at every status first.
WHERE rn = 1;

-- Recovery is SUCCESS payments only, Jan-Jul (August has 8 days of data).
-- A VIEW = a saved query with a name. It stores no data; its SELECT re-runs every time someone reads it.
-- DROP VIEW IF EXISTS = remove the old one first.
DROP VIEW IF EXISTS stg_recovery;
-- stg_recovery = "money actually recovered": the rows behind every recovery number in files 05, 06, 07 and 08.
CREATE VIEW stg_recovery AS
-- Take every column of the clean payments table ...
SELECT * FROM stg_payments
-- ... but only SUCCESS payments with a CLEAN flag (FAILED, PENDING and REVERSED payments are not money in).
-- The view itself has no date filter, so it also holds August's 8 days; files 05 and 06 add a Jan-Jul filter.
WHERE payment_status = 'SUCCESS' AND quality_flag = 'CLEAN';

-- Audit
-- Audit query: per payment_status, the number of payments and their total in crores. Its result is not saved
-- (run_pipeline.py runs it and discards it); it is a quick check when the file is run by hand.
-- ROUND(x, 2) = round to 2 decimals. 1e7 = 10,000,000 rupees = 1 crore.
SELECT payment_status, COUNT(*) AS payments, ROUND(SUM(amount) / 1e7, 2) AS amount_cr
-- GROUP BY 1 = one group (one output row) per value of the 1st selected column, payment_status; COUNT and SUM
-- are worked out per group. ORDER BY 1 = sort by that same column, A to Z.
-- Real result: FAILED 3,677 / Rs 27.84 Cr, PENDING 2,535 / Rs 19.02 Cr, REVERSED 1,254 / Rs 9.47 Cr,
-- SUCCESS 17,534 / Rs 131.56 Cr (all months, August included).
FROM stg_payments GROUP BY 1 ORDER BY 1;
