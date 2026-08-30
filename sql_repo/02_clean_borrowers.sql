-- 02_clean_borrowers.sql
-- Deduplicates borrowers by taking the most recently updated record.

DROP TABLE IF EXISTS clean_borrowers;
CREATE TABLE clean_borrowers AS
SELECT borrower_id, name, phone, email, city, state, created_at
FROM (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY borrower_id ORDER BY updated_at DESC) as rn
    FROM borrowers
) WHERE rn = 1;
