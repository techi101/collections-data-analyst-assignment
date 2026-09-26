-- 04_monthly_metrics.sql
-- Aggregates clean data to calculate the true recovery and contact metrics.

DROP TABLE IF EXISTS monthly_metrics;
CREATE TABLE monthly_metrics AS
SELECT 
    strftime(p.event_at, '%Y-%m') as month,
    SUM(p.amount) as total_recovery,
    COUNT(DISTINCT p.account_id) as recovered_accounts,
    COUNT(DISTINCT a.account_id) as active_accounts,
    SUM(p.amount) / COUNT(DISTINCT a.account_id) as recovery_per_account
FROM clean_payments p
JOIN accounts a ON p.account_id = a.account_id
WHERE p.payment_status = 'SUCCESS'
GROUP BY 1
ORDER BY 1;
