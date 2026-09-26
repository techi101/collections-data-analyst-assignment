"""
Rebuild every number in this repo from the 17 raw CSV files.

    pip install duckdb pandas
    python run_pipeline.py

Steps:
  1. Create a fresh golden_dataset.duckdb and load every CSV as a raw table.
  2. Run sql_repo/01..08 in order (staging, metrics, channel, statistics, DiD).
  3. Run the forensic checks (Part 2 A-G) and save them to forensics_summary.json.
  4. Export golden_metrics.csv, results/*.csv and dashboard/data.json.

Nothing is read from a previous run, so a fresh clone reproduces the results.
"""
import glob
import json
import os
import re

import duckdb

DB = "golden_dataset.duckdb"
SQL_FILES = sorted(glob.glob("sql_repo/0*_*.sql"))


def run_sql_file(con, path):
    """Execute a .sql file statement by statement (full-line comments removed first)."""
    text = open(path, encoding="utf-8").read()
    text = "\n".join(line for line in text.splitlines() if not line.strip().startswith("--"))
    for stmt in text.split(";"):
        if stmt.strip():
            con.execute(stmt)


def one(con, sql):
    return con.execute(sql).fetchone()


def rows(con, sql):
    df = con.execute(sql).fetchdf()
    return json.loads(df.to_json(orient="records"))


def main():
    if os.path.exists(DB):
        os.remove(DB)
    con = duckdb.connect(DB)

    # 1. raw tables
    for csv in sorted(glob.glob("*.csv")):
        name = os.path.splitext(os.path.basename(csv))[0]
        if name in ("golden_metrics", "data_dictionary"):
            continue
        con.execute(f"CREATE TABLE {name} AS SELECT * FROM read_csv_auto('{csv}')")
    print("Loaded raw tables:", len(con.execute("SHOW TABLES").fetchall()))

    # 2. SQL repository
    for path in SQL_FILES:
        run_sql_file(con, path)
        print("ran", path)

    # 3. forensic checks
    f = {}
    raw_rows, ids, dup_rows = one(con, "SELECT COUNT(*), COUNT(DISTINCT payment_id), COUNT(*) - COUNT(DISTINCT payment_id) FROM payments")
    exact = one(con, "SELECT COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM payments)) FROM payments")[0]
    succ_dup = one(con, """SELECT COUNT(*), ROUND(SUM(amount)/1e7, 2) FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY event_at) rn FROM payments)
        WHERE rn > 1 AND payment_status = 'SUCCESS'""")
    ref_groups, ref_same_acct = one(con, """SELECT COUNT(*), SUM(CASE WHEN accts = 1 THEN 1 ELSE 0 END) FROM (
        SELECT payment_reference, COUNT(DISTINCT account_id) accts FROM stg_payments
        WHERE payment_reference IS NOT NULL GROUP BY 1 HAVING COUNT(*) > 1)""")
    old_method = rows(con, """
        WITH old AS (SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY payment_reference ORDER BY event_at) rn
                                    FROM payments) WHERE rn = 1 AND payment_status = 'SUCCESS'),
             m_new AS (SELECT strftime(event_at, '%Y-%m') m, SUM(amount) a FROM stg_recovery GROUP BY 1),
             m_old AS (SELECT strftime(event_at, '%Y-%m') m, SUM(amount) a FROM old GROUP BY 1)
        SELECT m_new.m AS month, ROUND(m_new.a/1e7, 2) AS correct_cr, ROUND(m_old.a/1e7, 2) AS old_method_cr,
               ROUND(100 * (1 - m_old.a / m_new.a), 1) AS old_method_deleted_pct
        FROM m_new JOIN m_old USING (m) WHERE m_new.m < '2026-08' ORDER BY 1""")
    f["A_duplicate_payments"] = {
        "raw_rows": raw_rows, "distinct_payment_ids": ids,
        "duplicate_rows_by_payment_id": dup_rows, "of_which_exact_copies": exact,
        "duplicate_success_rows": succ_dup[0], "duplicate_success_cr": succ_dup[1],
        "payment_reference_groups_with_repeats": ref_groups,
        "reference_groups_within_one_account": ref_same_acct,
        "old_reference_dedup_by_month": old_method,
        "verdict": "Real duplicates are repeated payment_ids (about 2% of successful value). "
                   "Repeated payment_references are collisions between different accounts, not duplicates; "
                   "deduplicating on them deleted real payments, increasingly in later months.",
    }
    attr = rows(con, "SELECT * FROM channel_attribution")
    nc = next(r for r in attr if r["channel"] == "NO_CONTACT_30D")
    f["B_attribution"] = {
        "payments_with_no_contact_in_prior_30_days": nc["payments"],
        "share_pct": nc["share_of_payments_pct"],
        "verdict": "Most payments had no contact on any channel in the 30 days before; campaign-level "
                   "joins without a time window credit campaigns with these self-cure payments.",
    }
    f["C_timezones"] = {"calls_by_timezone": rows(con, "SELECT timezone, COUNT(*) calls FROM calls GROUP BY 1 ORDER BY 1"),
                        "verdict": "Calls are stored in local time for three zones; stg_calls converts to UTC."}
    f["D_dispositions"] = {
        "codes": rows(con, """SELECT disposition_code, COUNT(*) n FROM call_dispositions
                              WHERE disposition_code IN ('PTP','PROMISE_TO_PAY') GROUP BY 1 ORDER BY 1"""),
        "versions_with_both_codes": one(con, """SELECT COUNT(DISTINCT disposition_version) FROM call_dispositions
                                               WHERE disposition_code = 'PROMISE_TO_PAY'""")[0],
        "raw_rows": one(con, "SELECT COUNT(*) FROM call_dispositions")[0],
        "distinct_calls": one(con, "SELECT COUNT(DISTINCT call_id) FROM call_dispositions")[0],
        "verdict": "PTP and PROMISE_TO_PAY both occur in every schema version; counting one misses about half of promises.",
    }
    f["E_agents"] = rows(con, "SELECT * FROM (SELECT COUNT(*) agent_ids, SUM(CASE WHEN attributes_unreliable THEN 1 ELSE 0 END) conflicting, ROUND(AVG(employee_codes_seen),1) avg_codes FROM stg_agents)")[0]
    f["E_agents"]["distinct_names_in_table"] = one(con, "SELECT COUNT(DISTINCT agent_name) FROM agents")[0]
    f["E_agents"]["verdict"] = ("Agent master data is inconsistent (codes and names change per row); "
                                "agent_id is used as the key and no per-person claims are made.")
    f["F_portfolio_mix"] = rows(con, """
        SELECT strftime(p.event_at, '%Y-%m') AS month,
               ROUND(100.0 * AVG(CASE WHEN a.dpd <= 30 THEN 1 ELSE 0 END), 1) AS early_dpd_share_pct,
               ROUND(100.0 * AVG(CASE WHEN a.dpd > 90 THEN 1 ELSE 0 END), 1) AS late_dpd_share_pct
        FROM stg_recovery p JOIN accounts a USING (account_id)
        WHERE p.event_at < DATE '2026-08-01' GROUP BY 1 ORDER BY 1""")

    metrics = con.execute("SELECT * FROM golden_monthly_metrics").fetchdf()
    metrics["mom_recovery_pct"] = (metrics["total_recovery_inr"].pct_change() * 100).round(1)
    f["headline"] = {
        "jan_recovery_cr": float(metrics.iloc[0]["total_recovery_cr"]),
        "jul_recovery_cr": float(metrics.iloc[-1]["total_recovery_cr"]),
        "mar_mom_pct": float(metrics.loc[metrics["month"] == "2026-03", "mom_recovery_pct"].iloc[0]),
        "feb_mom_pct": float(metrics.loc[metrics["month"] == "2026-02", "mom_recovery_pct"].iloc[0]),
        "mean_mom_feb_to_jul_pct": round(float(metrics["mom_recovery_pct"].iloc[1:].mean()), 1),
        "verdict": "Recovery is flat Jan-Jul. The +11% is March alone, rebounding from a -9.1% February; not a trend.",
    }
    f["channel_attribution"] = attr
    f["channel_lift"] = rows(con, "SELECT * FROM channel_lift")
    f["did"] = {"groups": rows(con, "SELECT * FROM did_results"),
                "estimate_pp": one(con, """SELECT ROUND(
                    (MAX(CASE WHEN grp='TREATMENT_FIELD' AND period='POST' THEN paid_within_30d_pct END)
                   - MAX(CASE WHEN grp='TREATMENT_FIELD' AND period='PRE'  THEN paid_within_30d_pct END))
                  - (MAX(CASE WHEN grp='CONTROL_DIGITAL' AND period='POST' THEN paid_within_30d_pct END)
                   - MAX(CASE WHEN grp='CONTROL_DIGITAL' AND period='PRE'  THEN paid_within_30d_pct END)), 2)
                   FROM did_results""")[0]}

    # 95% confidence intervals (normal approximation) so small differences
    # are not read as effects.
    for r in f["channel_lift"]:
        p_, n_ = r["paid_within_30d_pct"] / 100, r["accounts_reached"]
        se = (p_ * (1 - p_) / n_) ** 0.5 * 100
        r["lift_ci95_pp"] = [round(r["lift_pp"] - 1.96 * se, 2), round(r["lift_pp"] + 1.96 * se, 2)]
    g = {(r["grp"], r["period"]): r for r in f["did"]["groups"]}
    var = 0.0
    for key in g:
        p_, n_ = g[key]["paid_within_30d_pct"] / 100, g[key]["targeting_rows"]
        var += p_ * (1 - p_) / n_
    se = var ** 0.5 * 100
    est = f["did"]["estimate_pp"]
    f["did"]["ci95_pp"] = [round(est - 1.96 * se, 2), round(est + 1.96 * se, 2)]
    f["did"]["note"] = ("Rows are targeting events, not independent accounts, so the interval is if anything "
                        "too narrow. An interval that includes 0 means no detectable effect.")

    with open("forensics_summary.json", "w", encoding="utf-8") as fh:
        json.dump(f, fh, indent=2, default=str)

    # 4. exports
    metrics.to_csv("golden_metrics.csv", index=False)
    os.makedirs("results", exist_ok=True)
    for t in ("channel_attribution", "channel_lift", "did_results"):
        con.execute(f"SELECT * FROM {t}").fetchdf().to_csv(f"results/{t}.csv", index=False)
    dashboard = {
        "monthly_metrics": json.loads(metrics.fillna(0).to_json(orient="records")),
        "channel_attribution": attr,
        "channel_lift": f["channel_lift"],
        "forensics": {k: v for k, v in f.items() if k.startswith(("A_", "B_", "D_", "E_", "headline"))},
        "did": f["did"],
    }
    with open("dashboard/data.json", "w", encoding="utf-8") as fh:
        json.dump(dashboard, fh, indent=2, default=str)

    print("\nMonthly metrics:\n", metrics[["month", "total_recovery_cr", "mom_recovery_pct", "paying_account_rate_pct",
                                          "answer_rate_pct", "rpc_rate_pct", "ptp_kept_rate_pct",
                                          "recovery_per_agent_hour_inr"]].to_string(index=False))
    print("\nChannel attribution:\n", con.execute("SELECT * FROM channel_attribution").fetchdf().to_string(index=False))
    print("\nChannel lift:\n", con.execute("SELECT * FROM channel_lift").fetchdf().to_string(index=False))
    print("\nDiD:\n", con.execute("SELECT * FROM did_results").fetchdf().to_string(index=False), "\nestimate_pp =", f["did"]["estimate_pp"], "ci95 =", f["did"]["ci95_pp"])
    print("Lift CIs:", [(r["channel"], r["lift_pp"], r["lift_ci95_pp"]) for r in f["channel_lift"]])
    print("\nDuplicates:", {k: v for k, v in f["A_duplicate_payments"].items() if k not in ("old_reference_dedup_by_month", "verdict")})
    con.close()


if __name__ == "__main__":
    main()
