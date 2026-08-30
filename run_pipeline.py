import duckdb, pandas as pd, json

con = duckdb.connect('golden_dataset.duckdb')

# Run all staging transforms from SQL
for sql_file in ['sql_repo/01_staging_payments.sql', 'sql_repo/02_staging_agents.sql',
                  'sql_repo/03_staging_calls.sql', 'sql_repo/04_staging_dispositions.sql']:
    with open(sql_file) as f:
        sql = f.read()
    # Strip comment blocks and split on ; then execute each statement
    for stmt in sql.split(';'):
        stmt = stmt.strip()
        if stmt and not stmt.startswith('--'):
            try:
                con.execute(stmt)
            except Exception as e:
                if 'already exists' not in str(e).lower():
                    print(f"Warning in {sql_file}: {e}")

# Build golden monthly metrics
golden_sql = open('sql_repo/05_golden_monthly_metrics.sql').read()
# Execute only the CREATE TABLE part
create_part = golden_sql[:golden_sql.rfind('ORDER BY r.month;') + len('ORDER BY r.month;')]
for stmt in create_part.split(';'):
    stmt = stmt.strip()
    if stmt and not stmt.startswith('--'):
        try:
            con.execute(stmt)
        except Exception as e:
            print(f"Warning: {e}")

# Export golden metrics
metrics_df = con.execute("SELECT * FROM golden_monthly_metrics").fetchdf()
metrics_df['mom_recovery_pct'] = metrics_df['total_recovery_inr'].pct_change() * 100
metrics_df.to_csv('golden_metrics.csv', index=False)
print("Golden metrics:\n", metrics_df[['month','total_recovery_cr','recovery_rate_pct','contact_rate_rpc_pct','ptp_rate_pct','ptp_kept_rate_pct','recovery_per_agent_hour_inr','mom_recovery_pct']].to_string())

# Channel analysis
channel_df = con.execute("""
    SELECT cam.channel,
        COUNT(DISTINCT p.account_id) AS accounts_recovered,
        SUM(p.amount)/1e7 AS recovered_cr,
        ROUND(AVG(p.amount), 0) AS avg_payment
    FROM campaigns cam
    JOIN daily_targeting dt ON cam.campaign_id = dt.campaign_id
    JOIN clean_payments p ON dt.account_id = p.account_id
    WHERE p.payment_status = 'SUCCESS'
    GROUP BY cam.channel ORDER BY recovered_cr DESC
""").fetchdf()
print("\nChannel performance:\n", channel_df)

# WhatsApp funnel
wa_df = con.execute("SELECT event_type, COUNT(*) cnt, COUNT(DISTINCT account_id) accts FROM whatsapp_events GROUP BY 1 ORDER BY 2 DESC").fetchdf()
print("\nWhatsApp funnel:\n", wa_df)

# Save for dashboard
all_data = {
    "monthly_metrics": metrics_df.fillna(0).to_dict('records'),
    "channel_perf": channel_df.to_dict('records'),
    "whatsapp_funnel": wa_df.to_dict('records'),
}
with open('dashboard/data.json', 'w') as f:
    json.dump(all_data, f, indent=2, default=str)
print("\nDashboard data saved.")
