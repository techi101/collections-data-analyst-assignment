-- ============================================================
-- 06_channel_analysis.sql
-- Channel performance: which channel drives the most recovery
-- Used for 10 Cr investment recommendation
-- ============================================================

-- Recovery by channel (from campaigns)
SELECT 
    cam.channel,
    COUNT(DISTINCT p.account_id) AS accounts_recovered,
    SUM(p.amount) AS total_recovered_inr,
    SUM(p.amount) / 1e7 AS total_recovered_cr,
    ROUND(AVG(p.amount), 0) AS avg_payment_size_inr
FROM campaigns cam
JOIN daily_targeting dt ON cam.campaign_id = dt.campaign_id
JOIN clean_payments p ON dt.account_id = p.account_id
WHERE p.payment_status = 'SUCCESS'
GROUP BY cam.channel
ORDER BY total_recovered_inr DESC;

-- WhatsApp channel: response rate
SELECT 
    event_type,
    COUNT(*) AS events,
    COUNT(DISTINCT account_id) AS unique_accounts
FROM whatsapp_events
GROUP BY event_type
ORDER BY events DESC;

-- SMS channel: response rate
SELECT 
    event_type,
    COUNT(*) AS events,
    COUNT(DISTINCT account_id) AS unique_accounts
FROM sms_events
GROUP BY event_type
ORDER BY events DESC;

-- Field visit outcome → payment conversion
SELECT 
    fv.outcome,
    COUNT(*) AS visits,
    COUNT(DISTINCT p.account_id) AS accounts_that_paid,
    ROUND(COUNT(DISTINCT p.account_id) * 100.0 / COUNT(*), 2) AS conversion_pct
FROM field_visits fv
LEFT JOIN clean_payments p 
    ON fv.account_id = p.account_id 
    AND p.payment_status = 'SUCCESS'
    AND p.event_at > fv.event_at
    AND p.event_at < fv.event_at + INTERVAL '30 days'
GROUP BY fv.outcome
ORDER BY visits DESC;
