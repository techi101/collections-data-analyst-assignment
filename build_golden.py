import duckdb
import pandas as pd

def build_golden_dataset():
    print("Connecting to DuckDB...")
    con = duckdb.connect('golden_dataset.duckdb')
    
    print("Building clean tables...")
    
    # 1. Clean Payments (deduplicate)
    con.execute("DROP TABLE IF EXISTS clean_payments")
    con.execute("""
        CREATE TABLE clean_payments AS
        SELECT payment_id, account_id, borrower_id, event_at, payment_reference, amount, payment_status, payment_method
        FROM (
            SELECT *, ROW_NUMBER() OVER(PARTITION BY payment_reference ORDER BY event_at) as rn
            FROM payments
        ) WHERE rn = 1
    """)
    
    # 2. Clean Borrowers (deduplicate)
    con.execute("DROP TABLE IF EXISTS clean_borrowers")
    con.execute("""
        CREATE TABLE clean_borrowers AS
        SELECT borrower_id, name, phone, email, city, state, created_at
        FROM (
            SELECT *, ROW_NUMBER() OVER(PARTITION BY borrower_id ORDER BY updated_at DESC) as rn
            FROM borrowers
        ) WHERE rn = 1
    """)
    
    # 3. Clean Agents (merge duplicate identities)
    con.execute("DROP TABLE IF EXISTS clean_agents")
    con.execute("""
        CREATE TABLE clean_agents AS
        SELECT MIN(agent_id) as canonical_agent_id, agent_name, MIN(team) as team
        FROM agents
        GROUP BY agent_name
    """)
    
    # 4. Create monthly performance metrics for accounts and campaigns
    # This addresses "What happened" and "Is the reported 11% improvement real?"
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
        WHERE p.payment_status = 'Success'
        GROUP BY 1
        ORDER BY 1
    """)
    
    # 5. Extract monthly metrics for analysis
    metrics_df = con.execute("SELECT * FROM monthly_metrics").fetchdf()
    metrics_df.to_csv('golden_metrics.csv', index=False)
    print("Golden dataset built and metrics extracted.")

if __name__ == '__main__':
    build_golden_dataset()
