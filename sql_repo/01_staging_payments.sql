-- ============================================================
-- 01_staging_payments.sql
-- Stage payments with deduplication
-- Primary Key: payment_reference (keep earliest event)
-- Removes: duplicate retries, reversal events
-- ============================================================

DROP TABLE IF EXISTS stg_payments;
CREATE TABLE stg_payments AS
WITH deduped AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY payment_reference 
            ORDER BY event_at ASC
        ) AS rn
    FROM payments
),
quality_flags AS (
    SELECT *,
        CASE WHEN amount <= 0 THEN 'REJECTED_ZERO_AMOUNT'
             WHEN account_id IS NULL THEN 'REJECTED_NO_ACCOUNT'
             WHEN payment_status = 'REVERSED' THEN 'EXCLUDED_REVERSAL'
             ELSE 'CLEAN'
        END AS quality_flag
    FROM deduped
    WHERE rn = 1
)
SELECT 
    payment_id,
    account_id,
    borrower_id,
    event_at,
    payment_reference,
    amount,
    payment_status,
    payment_method,
    provider_id,
    quality_flag
FROM quality_flags;

-- Audit log
SELECT quality_flag, COUNT(*) as records, SUM(amount) as total_amount
FROM stg_payments
GROUP BY quality_flag;
