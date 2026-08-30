import duckdb
import pandas as pd
import json

def run_forensics():
    # Connect to DuckDB
    con = duckdb.connect(database='golden_dataset.duckdb', read_only=False)
    
    # 1. Load CSVs into DuckDB tables
    tables = [
        'borrowers', 'accounts', 'agents', 'agent_sessions', 'campaigns', 
        'daily_targeting', 'calls', 'call_attempts', 'call_dispositions', 
        'whatsapp_events', 'sms_events', 'field_visits', 'promises_to_pay', 
        'payments', 'vendor_telephony', 'complaints', 'account_status_history'
    ]
    
    print("Loading CSVs into DuckDB...")
    for table in tables:
        con.execute(f"CREATE TABLE IF NOT EXISTS {table} AS SELECT * FROM read_csv_auto('{table}.csv')")
        
    forensics = {}
    
    print("Running Data Forensics...")
    # A. Duplicate payments
    dupe_payments = con.execute("""
        SELECT payment_reference, COUNT(*) as cnt 
        FROM payments 
        GROUP BY payment_reference 
        HAVING cnt > 1
    """).fetchdf()
    forensics['duplicate_payments'] = len(dupe_payments)
    
    # E. Agent identity problems
    agent_identities = con.execute("""
        SELECT agent_name, COUNT(DISTINCT agent_id) as num_ids 
        FROM agents 
        GROUP BY agent_name 
        HAVING num_ids > 1
    """).fetchdf()
    forensics['agent_identity_problems'] = len(agent_identities)

    # C. Timezone problems in calls vs accounts
    timezone_issues = con.execute("""
        SELECT COUNT(*) as calls_with_tz_mismatch
        FROM calls c
        JOIN accounts a ON c.account_id = a.account_id
        WHERE c.timezone != a.timezone
    """).fetchdf()
    forensics['timezone_mismatches'] = int(timezone_issues.iloc[0, 0])
    
    # Check for missing values in critical fields (payments)
    missing_payments = con.execute("""
        SELECT COUNT(*) as missing_amt
        FROM payments
        WHERE amount IS NULL OR account_id IS NULL
    """).fetchdf()
    forensics['missing_payment_info'] = int(missing_payments.iloc[0, 0])
    
    # Duplicates in borrowers
    dupe_borrowers = con.execute("""
        SELECT borrower_id, COUNT(*) as cnt
        FROM borrowers
        GROUP BY borrower_id
        HAVING cnt > 1
    """).fetchdf()
    forensics['duplicate_borrower_ids'] = len(dupe_borrowers)
    
    # Duplicates in accounts
    dupe_accounts = con.execute("""
        SELECT account_id, COUNT(*) as cnt
        FROM accounts
        GROUP BY account_id
        HAVING cnt > 1
    """).fetchdf()
    forensics['duplicate_account_ids'] = len(dupe_accounts)

    print(json.dumps(forensics, indent=2))
    
    with open('forensics_summary.json', 'w') as f:
        json.dump(forensics, f, indent=2)

if __name__ == '__main__':
    run_forensics()
