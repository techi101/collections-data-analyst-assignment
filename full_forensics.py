import duckdb
import pandas as pd
import json

con = duckdb.connect('golden_dataset.duckdb')

# ============================================================
# FORENSICS A: DUPLICATE PAYMENTS
# ============================================================
print("=== A. DUPLICATE PAYMENTS FORENSICS ===")
raw_success = con.execute("SELECT SUM(amount) as amt FROM payments WHERE payment_status='SUCCESS'").fetchdf().iloc[0,0]
clean_success = con.execute("SELECT SUM(amount) as amt FROM clean_payments WHERE payment_status='SUCCESS'").fetchdf().iloc[0,0]
dup_count = con.execute("SELECT COUNT(*) as cnt FROM payments p WHERE payment_status='SUCCESS' AND EXISTS (SELECT 1 FROM (SELECT payment_reference, MIN(payment_id) as first_id FROM payments GROUP BY payment_reference) sub WHERE sub.payment_reference=p.payment_reference AND sub.first_id != p.payment_id)").fetchdf().iloc[0,0]
print(f"Raw SUCCESS total: Rs {raw_success/1e7:.2f} Cr")
print(f"Clean SUCCESS total: Rs {clean_success/1e7:.2f} Cr")
print(f"Inflation from duplicates: Rs {(raw_success - clean_success)/1e7:.2f} Cr ({((raw_success-clean_success)/clean_success*100):.1f}%)")
print(f"Duplicate SUCCESS payment events: {dup_count}")

# ============================================================
# FORENSICS B: ATTRIBUTION ERRORS
# ============================================================
print("\n=== B. ATTRIBUTION ERRORS ===")
# Check if payments happen BEFORE the most recent interaction
attr_check = con.execute("""
    SELECT COUNT(*) as payments_before_any_call
    FROM clean_payments p
    WHERE payment_status = 'SUCCESS'
    AND NOT EXISTS (
        SELECT 1 FROM calls c 
        WHERE c.account_id = p.account_id 
        AND c.event_at <= p.event_at
    )
""").fetchdf().iloc[0,0]
print(f"Payments with NO prior call interaction: {attr_check} (attribution to latest contact may be wrong)")

# ============================================================
# FORENSICS C: TIMEZONE PROBLEMS
# ============================================================
print("\n=== C. TIMEZONE PROBLEMS ===")
tz_dist = con.execute("SELECT timezone, COUNT(*) cnt FROM calls GROUP BY 1").fetchdf()
print(tz_dist)
# Show how this distorts hourly analysis
print("Calls stored in UTC that appear to be nighttime in India:")
utc_night = con.execute("SELECT COUNT(*) cnt FROM calls WHERE timezone='UTC' AND CAST(strftime(event_at, '%H') AS INT) BETWEEN 0 AND 5").fetchdf().iloc[0,0]
print(f"  UTC calls between 00:00-05:59 UTC = {utc_night} (these are 05:30-11:30 IST, NOT nighttime — timezone bug)")

# ============================================================
# FORENSICS D: VENDOR/DISPOSITION MAPPING CHANGES
# ============================================================
print("\n=== D. VENDOR & DISPOSITION CODE CHANGES ===")
# PTP codes: PROMISE_TO_PAY (legacy) and PTP (v1/v2) are the SAME metric
ptp_legacy = con.execute("SELECT COUNT(*) FROM call_dispositions WHERE disposition_code='PROMISE_TO_PAY' AND disposition_version='legacy'").fetchdf().iloc[0,0]
ptp_v1 = con.execute("SELECT COUNT(*) FROM call_dispositions WHERE disposition_code='PTP' AND disposition_version IN ('v1','v2')").fetchdf().iloc[0,0]
print(f"'PROMISE_TO_PAY' (legacy) events: {ptp_legacy}")
print(f"'PTP' (v1/v2) events: {ptp_v1}")
print(f"If legacy code is missed, PTP Rate is undercounted by {ptp_legacy}/{ptp_legacy+ptp_v1} = {ptp_legacy/(ptp_legacy+ptp_v1)*100:.1f}% of true PTPs")

inactive_vendors = con.execute("SELECT vendor_name, COUNT(*) cnt FROM vendor_telephony WHERE status='INACTIVE' GROUP BY 1").fetchdf()
active_vendors = con.execute("SELECT vendor_name, COUNT(*) cnt FROM vendor_telephony WHERE status='ACTIVE' GROUP BY 1").fetchdf()
print(f"\nActive vendors: {active_vendors.to_dict('records')}")
print(f"Inactive (churned) vendors: {inactive_vendors.to_dict('records')}")

# ============================================================
# FORENSICS E: AGENT IDENTITY PROBLEMS
# ============================================================
print("\n=== E. AGENT IDENTITY PROBLEMS ===")
dup_agents = con.execute("SELECT agent_name, COUNT(DISTINCT agent_id) num_ids, COUNT(DISTINCT employee_code) num_ecodes FROM agents GROUP BY agent_name HAVING num_ids > 1").fetchdf()
print(f"Agents with multiple agent_ids: {len(dup_agents)}")
print(dup_agents.head(5))

# ============================================================
# FORENSICS F: PORTFOLIO MIX CHANGES
# ============================================================
print("\n=== F. PORTFOLIO MIX CHANGES ===")
# Check DPD distribution over time by looking at account_status_history
mix = con.execute("""
    SELECT 
        strftime(event_at, '%Y-%m') as month,
        COUNT(DISTINCT account_id) as accounts_active
    FROM account_status_history
    WHERE status IN ('ACTIVE', 'IN_COLLECTION')
    GROUP BY 1
    ORDER BY 1
""").fetchdf()
print(mix)

# Check average DPD across accounts  
dpd_dist = con.execute("SELECT dpd, COUNT(*) cnt FROM accounts GROUP BY 1 ORDER BY 1").fetchdf()
print("\nDPD Distribution (snapshot):")
print(dpd_dist)

# ============================================================
# FORENSICS G: DENOMINATOR MANIPULATION
# ============================================================
print("\n=== G. DENOMINATOR MANIPULATION ===")
# Check if accounts are disappearing from the active pool post-collection
total_accounts = con.execute("SELECT COUNT(DISTINCT account_id) FROM accounts").fetchdf().iloc[0,0]
accts_with_payment = con.execute("SELECT COUNT(DISTINCT account_id) FROM clean_payments WHERE payment_status='SUCCESS'").fetchdf().iloc[0,0]
accts_with_no_activity = con.execute("""
    SELECT COUNT(*) FROM accounts a 
    WHERE NOT EXISTS (SELECT 1 FROM calls c WHERE c.account_id = a.account_id)
    AND NOT EXISTS (SELECT 1 FROM whatsapp_events w WHERE w.account_id = a.account_id)
""").fetchdf().iloc[0,0]
print(f"Total accounts in portfolio: {total_accounts}")
print(f"Accounts that recovered (have SUCCESS payment): {accts_with_payment} ({accts_with_payment/total_accounts*100:.1f}%)")
print(f"Accounts with NO calls AND NO WhatsApp: {accts_with_no_activity} ({accts_with_no_activity/total_accounts*100:.1f}%) — potentially excluded from denominator!")

# ============================================================
# FORENSICS SUMMARY
# ============================================================
findings = {
    "A_duplicate_payments": {
        "raw_recovery_cr": round(raw_success/1e7, 2),
        "clean_recovery_cr": round(clean_success/1e7, 2),
        "inflation_cr": round((raw_success - clean_success)/1e7, 2),
        "inflation_pct": round((raw_success-clean_success)/clean_success*100, 1),
        "duplicate_event_count": int(dup_count)
    },
    "B_attribution_errors": {
        "payments_with_no_prior_call": int(attr_check),
        "verdict": "Payments being attributed to last channel without verifying chronological order"
    },
    "C_timezone_issues": {
        "timezone_distribution": tz_dist.to_dict('records'),
        "verdict": "Calls split 33/33/33 across UTC, IST, Dubai - any hourly analysis is broken without normalization"
    },
    "D_disposition_code_changes": {
        "legacy_ptp_events": int(ptp_legacy),
        "v1v2_ptp_events": int(ptp_v1),
        "undercount_pct": round(ptp_legacy/(ptp_legacy+ptp_v1)*100, 1),
        "verdict": "PROMISE_TO_PAY (legacy) and PTP (v1/v2) are the same metric — must be unified"
    },
    "E_agent_identity_problems": {
        "agents_with_multiple_ids": len(dup_agents)
    },
    "G_denominator_manipulation": {
        "total_accounts": int(total_accounts),
        "accounts_recovered": int(accts_with_payment),
        "recovery_rate_pct": round(accts_with_payment/total_accounts*100, 1),
        "accounts_with_no_activity": int(accts_with_no_activity),
        "verdict": "Accounts with no interactions may be silently excluded from conversion denominators"
    }
}

with open('forensics_full.json', 'w') as f:
    json.dump(findings, f, indent=2)

print("\n=== FORENSICS SUMMARY SAVED TO forensics_full.json ===")
