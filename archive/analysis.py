import duckdb
import pandas as pd
import json
import nbformat as nbf

def run_analysis():
    con = duckdb.connect('golden_dataset.duckdb')
    
    # Recreate monthly metrics properly
    con.execute("DROP TABLE IF EXISTS monthly_metrics")
    con.execute("""
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
        ORDER BY 1
    """)
    
    # Q1 & Q3: Real MoM growth
    mom_df = con.execute("""
        SELECT 
            month, 
            total_recovery, 
            LAG(total_recovery) OVER(ORDER BY month) as prev_month_recovery, 
            (total_recovery - LAG(total_recovery) OVER(ORDER BY month)) / LAG(total_recovery) OVER(ORDER BY month) * 100 as mom_growth_pct 
        FROM monthly_metrics
    """).fetchdf()
    
    avg_mom_growth = mom_df['mom_growth_pct'].mean()
    
    # Let's also check the "Reported" growth using the raw payments (with duplicates)
    raw_mom_df = con.execute("""
        SELECT 
            strftime(event_at, '%Y-%m') as month,
            SUM(amount) as raw_recovery
        FROM payments
        WHERE payment_status IN ('SUCCESS', 'Success')
        GROUP BY 1
        ORDER BY 1
    """).fetchdf()
    raw_mom_df['mom'] = raw_mom_df['raw_recovery'].pct_change() * 100
    avg_raw_mom = raw_mom_df['mom'].mean()
    
    # Q4: Where to invest 10Cr? Let's check recovery per channel
    channel_recovery = con.execute("""
        SELECT 
            c.channel,
            COUNT(DISTINCT c.campaign_id) as num_campaigns,
            SUM(p.amount) as total_recovered,
            COUNT(DISTINCT p.account_id) as unique_accounts_recovered
        FROM campaigns c
        JOIN daily_targeting dt ON c.campaign_id = dt.campaign_id
        JOIN clean_payments p ON dt.account_id = p.account_id 
        WHERE p.payment_status = 'SUCCESS'
        GROUP BY 1
        ORDER BY total_recovered DESC
    """).fetchdf()
    
    # Save findings for memo
    findings = {
        "actual_avg_mom_growth": float(avg_mom_growth),
        "raw_reported_avg_mom_growth": float(avg_raw_mom),
        "channel_performance": channel_recovery.to_dict(orient='records')
    }
    
    with open('analysis_findings.json', 'w') as f:
        json.dump(findings, f, indent=2)
        
    # Generate Notebook
    nb = nbf.v4.new_notebook()
    nb['cells'] = [
        nbf.v4.new_markdown_cell("# Collections Analysis"),
        nbf.v4.new_code_cell("import duckdb\nimport pandas as pd\ncon = duckdb.connect('golden_dataset.duckdb')"),
        nbf.v4.new_markdown_cell("## Is the reported 11% improvement real?"),
        nbf.v4.new_code_cell("mom_df = con.execute('SELECT month, total_recovery, LAG(total_recovery) OVER(ORDER BY month) as prev, (total_recovery - LAG(total_recovery) OVER(ORDER BY month)) / LAG(total_recovery) OVER(ORDER BY month) * 100 as mom_growth_pct FROM monthly_metrics').fetchdf()\ndisplay(mom_df)"),
        nbf.v4.new_markdown_cell(f"**Conclusion**: The true MoM growth is {avg_mom_growth:.2f}%, whereas the raw un-deduplicated data showed {avg_raw_mom:.2f}%."),
        nbf.v4.new_markdown_cell("## Channel Performance (10 Cr Investment)"),
        nbf.v4.new_code_cell("channel_df = con.execute('SELECT c.channel, SUM(p.amount) as total_recovered FROM campaigns c JOIN daily_targeting dt ON c.campaign_id = dt.campaign_id JOIN clean_payments p ON dt.account_id = p.account_id WHERE p.payment_status = \\'SUCCESS\\' GROUP BY 1 ORDER BY 2 DESC').fetchdf()\ndisplay(channel_df)")
    ]
    with open('notebooks/analysis.ipynb', 'w') as f:
        nbf.write(nb, f)

if __name__ == '__main__':
    run_analysis()
