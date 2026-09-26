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

DROP TABLE IF EXISTS stg_payments;
CREATE TABLE stg_payments AS
WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY event_at, payment_reference) AS rn,
        COUNT(*)     OVER (PARTITION BY payment_id) AS copies
    FROM payments
)
SELECT
    payment_id, account_id, borrower_id, event_at, payment_reference,
    amount, payment_status, payment_method, provider_id,
    copies - 1 AS duplicate_rows_removed,
    CASE WHEN amount <= 0          THEN 'REJECTED_ZERO_AMOUNT'
         WHEN account_id IS NULL   THEN 'REJECTED_NO_ACCOUNT'
         ELSE 'CLEAN' END AS quality_flag
FROM ranked
WHERE rn = 1;

-- Recovery is SUCCESS payments only, Jan-Jul (August has 8 days of data).
DROP VIEW IF EXISTS stg_recovery;
CREATE VIEW stg_recovery AS
SELECT * FROM stg_payments
WHERE payment_status = 'SUCCESS' AND quality_flag = 'CLEAN';

-- Audit
SELECT payment_status, COUNT(*) AS payments, ROUND(SUM(amount) / 1e7, 2) AS amount_cr
FROM stg_payments GROUP BY 1 ORDER BY 1;
