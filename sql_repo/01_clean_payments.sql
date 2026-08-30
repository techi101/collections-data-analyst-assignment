-- 01_clean_payments.sql
-- Deduplicates payment retries and invalid events to create a clean payment source of truth.

DROP TABLE IF EXISTS clean_payments;
CREATE TABLE clean_payments AS
SELECT payment_id, account_id, borrower_id, event_at, payment_reference, amount, payment_status, payment_method
FROM (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY payment_reference ORDER BY event_at) as rn
    FROM payments
) WHERE rn = 1;
