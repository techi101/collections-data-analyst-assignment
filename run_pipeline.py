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
# WHAT THIS FILE IS: the "one button" that rebuilds the whole analysis from scratch. Think of a recipe card in a
# kitchen: take the 17 raw ingredient files (CSV = comma-separated values, a plain-text table), cook them through
# the 8 SQL recipe files in sql_repo/ in a fixed order, then plate the results into the output files.
# Real example: payments.csv has 25,500 rows but only 25,000 different payment_id values (500 duplicate rows).
# After this script runs, golden_metrics.csv says recovery was Rs 18.72 Cr in January and Rs 18.72 Cr in July
# (flat), and forensics_summary.json records that the OLD August method (dedup on payment_reference) would have
# shown only Rs 13.40 Cr for July, because it deleted real payments. That was the fake "decline".
# DuckDB = a small database engine that runs inside Python (no server to install). It keeps all tables in one
# file, golden_dataset.duckdb, and answers SQL (Structured Query Language = the language for asking tables questions).
# Overall flow: raw CSVs -> raw DuckDB tables -> sql_repo/01..08 (clean "stg_" tables + result tables)
#   -> forensic checks A-F + headline + 95% confidence intervals -> forensics_summary.json, golden_metrics.csv,
#   results/*.csv, dashboard/data.json -> summary tables printed on screen.
# It takes about 5 seconds and reads nothing from an earlier run, so anyone who clones the repo gets the same numbers.
#
# Standard library imports (they come with Python, nothing to install):
# glob: finds files by a name pattern, like "*.csv" = every file whose name ends in .csv
import glob
# json: turns Python dicts/lists into JSON text and back. JSON = the {"key": value} text format of
# forensics_summary.json and dashboard/data.json
import json
# os: talks to the operating system: does a file exist, delete a file, make a folder, split a file name
import os
# re: regular expressions (text patterns). It is imported but not used anywhere in this file.
import re

# Installed library (pip install duckdb pandas):
# duckdb: the in-process SQL database described above. pandas is not imported by name, but it must be installed:
# DuckDB's .fetchdf() returns a pandas DataFrame (a table object in Python, like a sheet in Excel).
import duckdb

# DB = name of the database file this script creates. It is listed in .gitignore (*.duckdb), so it is never committed.
DB = "golden_dataset.duckdb"
# SQL_FILES = the 8 SQL files, found with the pattern "sql_repo/0*_*.sql" (names like 01_staging_payments.sql),
# then sorted() by name so they run in the order 01, 02, ... 08. Order matters: 05 reads tables that 01-04 create.
SQL_FILES = sorted(glob.glob("sql_repo/0*_*.sql"))


# IN: con (an open DuckDB connection) + path (one .sql file)  ->  OUT: nothing returned; the file's statements run.
# WHY: con.execute() is given one statement at a time here, so the file is cut into statements at every ";".
# Example: run_sql_file(con, "sql_repo/01_staging_payments.sql") runs DROP TABLE, CREATE TABLE stg_payments,
#   DROP VIEW, CREATE VIEW stg_recovery and the audit SELECT, one after another.
def run_sql_file(con, path):
    """Execute a .sql file statement by statement (full-line comments removed first)."""
    # Read the whole file as one text string (encoding="utf-8" = read the bytes as normal UTF-8 text).
    text = open(path, encoding="utf-8").read()
    # Drop every line that starts with "--" once its leading spaces are removed. In SQL, "--" starts a comment.
    # This way a ";" written inside a comment can never cut a statement in the wrong place, and all the
    # whole-line study comments in sql_repo/ are thrown away before anything runs.
    # Only WHOLE comment lines are removed; a comment at the end of a code line (like "-- already UTC" in 03)
    # stays in the text and DuckDB itself ignores it.
    text = "\n".join(line for line in text.splitlines() if not line.strip().startswith("--"))
    # Cut the text at every ";" (the end of a SQL statement) and loop over the pieces.
    for stmt in text.split(";"):
        # Skip empty pieces (for example the blank text after the last ";"); run every other piece.
        if stmt.strip():
            con.execute(stmt)


# IN: con + one SQL query  ->  OUT: the FIRST row of the result as a tuple (a fixed, ordered list of values).
# WHY: many checks return a single row of numbers; this saves writing .execute(...).fetchone() each time.
# Example: one(con, "SELECT COUNT(*) FROM call_dispositions") -> (35000,), and [0] then gives 35000.
def one(con, sql):
    return con.execute(sql).fetchone()


# IN: con + one SQL query  ->  OUT: a list of dicts, one dict per result row ({column name: value}).
# WHY: a list of dicts can be written straight into forensics_summary.json by json.dump.
# Example: rows(con, "SELECT * FROM channel_lift") -> [{"channel": "FIELD", "accounts_reached": 14827, ...}, ...]
def rows(con, sql):
    # fetchdf() = fetch the whole result as a pandas DataFrame.
    df = con.execute(sql).fetchdf()
    # DataFrame -> JSON text (orient="records" = one {...} per row) -> back into Python lists/dicts with json.loads.
    # The round trip turns pandas/numpy number types into plain Python values that json.dump can write.
    return json.loads(df.to_json(orient="records"))


# IN: nothing (it reads the CSVs in the current folder)  ->  OUT: nothing returned; writes the output files and prints.
# WHY: one function holds the 4 steps listed in the docstring, so "python run_pipeline.py" rebuilds everything.
# Example: run from the repo folder -> prints "Loaded raw tables: 17", then "ran sql_repo/01_staging_payments.sql"
#   ... up to 08, then the monthly table (Jan 18.72 ... Jul 18.72), the channel tables and the duplicate counts.
def main():
    # Delete the old database file if it exists, so nothing from a previous run can leak into this one (a fresh start).
    if os.path.exists(DB):
        os.remove(DB)
    # Open (create) the database file. con = the connection; every query below goes through it.
    con = duckdb.connect(DB)

    # 1. raw tables
    # Step 1 loop: every .csv file in the repo folder, in name order (account_status_history.csv, accounts.csv, ...).
    for csv in sorted(glob.glob("*.csv")):
        # Table name = file name without its folder and without ".csv". Example: "payments.csv" -> "payments".
        name = os.path.splitext(os.path.basename(csv))[0]
        # Skip 2 CSVs that are not raw data: golden_metrics.csv is an OUTPUT of this very script, and
        # data_dictionary.csv only describes the columns. That leaves the 17 raw tables.
        if name in ("golden_metrics", "data_dictionary"):
            # continue = jump straight to the next file in the loop.
            continue
        # read_csv_auto = DuckDB reads the CSV and guesses each column's type by itself (text, number, timestamp).
        # Example: payments.event_at becomes a TIMESTAMP (date + time) and payments.amount a DOUBLE (decimal number).
        # CREATE TABLE ... AS SELECT = make a new table filled with the result of the SELECT.
        con.execute(f"CREATE TABLE {name} AS SELECT * FROM read_csv_auto('{csv}')")
    # SHOW TABLES lists every table; print how many were loaded (17).
    print("Loaded raw tables:", len(con.execute("SHOW TABLES").fetchall()))

    # 2. SQL repository
    # Step 2: run the 8 SQL files in order. A "staging" (stg_) table = a cleaned copy of a raw table that later queries
    # use instead of the raw one (stg_payments, stg_agents, stg_calls, stg_dispositions). The later files build the
    # result tables golden_monthly_metrics, stg_touches, channel_attribution, channel_lift and did_results.
    for path in SQL_FILES:
        run_sql_file(con, path)
        # Print progress so you can see which file ran (and which one failed, if one does).
        print("ran", path)

    # 3. forensic checks
    # f = the dict that becomes forensics_summary.json. Each key is one check (A_..., B_..., headline, did, ...).
    f = {}
    # Check A (duplicate payments), part 1: total rows, different payment_ids, and the gap between them.
    # COUNT(DISTINCT x) = how many different values of x. Real result: 25,500 rows, 25,000 ids -> 500 duplicate rows.
    # The query returns one row of 3 numbers, and Python "unpacks" them into 3 variables at once.
    raw_rows, ids, dup_rows = one(con, "SELECT COUNT(*), COUNT(DISTINCT payment_id), COUNT(*) - COUNT(DISTINCT payment_id) FROM payments")
    # How many duplicate rows are EXACT copies (every column equal)? SELECT DISTINCT * keeps one of each identical row,
    # so total rows minus distinct rows = exact copies. Real result: 486 (the other 14 differ only in
    # reference/method/provider, but share the same payment_id).
    exact = one(con, "SELECT COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM payments)) FROM payments")[0]
    # Successful duplicate rows and their money. A window function = a calculation over a group of related rows that
    # keeps every row (unlike GROUP BY, which squashes each group into one row). Here ROW_NUMBER() OVER (PARTITION BY
    # payment_id ORDER BY event_at) numbers the copies of each payment_id 1, 2, 3 ... (earliest first), so rn > 1 =
    # every copy after the first = a duplicate. 1e7 = 10,000,000 = 1 crore, so SUM(amount)/1e7 = rupees in crores.
    # Real result: 346 rows, Rs 2.59 Cr over ALL months including August's 8 days. (The Jan-Jul figure quoted in the
    # README is 325 rows, Rs 2.45 Cr, about 1.9% of raw successful value.)
    succ_dup = one(con, """SELECT COUNT(*), ROUND(SUM(amount)/1e7, 2) FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY event_at) rn FROM payments)
        WHERE rn > 1 AND payment_status = 'SUCCESS'""")
    # THE KEY CHECK, the trap of the August version. For every payment_reference that appears more than once, count how
    # many different accounts use it. If repeats were true duplicates, all rows of a reference would be ONE account.
    # GROUP BY 1 = group by the 1st selected column. HAVING COUNT(*) > 1 = keep only references that repeat (HAVING filters
    # groups AFTER grouping; WHERE filters rows BEFORE). CASE WHEN accts = 1 THEN 1 ELSE 0 END = 1 for a group inside one
    # account, else 0; SUM adds those up. IS NOT NULL = skip rows with no reference (NULL = "no value at all").
    # Real result: 3,407 repeated references, and 0 of them inside one account -> payment_reference is NOT a key.
    # Example: TXN0000062541 is used by ACC0005143 (Rs 96,247.47) and ACC0019406 (Rs 82,765.53): two real payments.
    ref_groups, ref_same_acct = one(con, """SELECT COUNT(*), SUM(CASE WHEN accts = 1 THEN 1 ELSE 0 END) FROM (
        SELECT payment_reference, COUNT(DISTINCT account_id) accts FROM stg_payments
        WHERE payment_reference IS NOT NULL GROUP BY 1 HAVING COUNT(*) > 1)""")
    # Re-create the WRONG August method only to measure the damage it did. A CTE (Common Table Expression) =
    # "WITH name AS (...)": a named helper result that exists only inside this one query.
    #   old   = one row per payment_reference (rn = 1), SUCCESS only: the dedup that deleted real payments.
    #   m_new = correct monthly recovery from stg_recovery;  m_old = monthly recovery under the old method.
    # strftime(event_at, '%Y-%m') turns a timestamp into its month text: 2026-07-23 20:25:20 -> "2026-07".
    # JOIN ... USING (m) = pair the rows whose month m is equal. WHERE m_new.m < '2026-08' drops partial August.
    # old_method_deleted_pct = 100 * (1 - old / correct) = share of real money the old method threw away.
    # Real result: January 18.72 vs 17.98 (4.0% deleted) rising to July 18.72 vs 13.40 (28.5% deleted).
    # References collide more the longer the data runs, so the old method deleted more each month: a fake decline.
    old_method = rows(con, """
        WITH old AS (SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY payment_reference ORDER BY event_at) rn
                                    FROM payments) WHERE rn = 1 AND payment_status = 'SUCCESS'),
             m_new AS (SELECT strftime(event_at, '%Y-%m') m, SUM(amount) a FROM stg_recovery GROUP BY 1),
             m_old AS (SELECT strftime(event_at, '%Y-%m') m, SUM(amount) a FROM old GROUP BY 1)
        SELECT m_new.m AS month, ROUND(m_new.a/1e7, 2) AS correct_cr, ROUND(m_old.a/1e7, 2) AS old_method_cr,
               ROUND(100 * (1 - m_old.a / m_new.a), 1) AS old_method_deleted_pct
        FROM m_new JOIN m_old USING (m) WHERE m_new.m < '2026-08' ORDER BY 1""")
    # Save every Check A number into f under the key "A_duplicate_payments", with a plain-words verdict.
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
    # Check B (attribution). channel_attribution was built by sql_repo/06: each payment is credited once, to its last
    # contact in the 30 days before it. Read it as a list of dicts.
    attr = rows(con, "SELECT * FROM channel_attribution")
    # next(...) = take the first row whose channel is "NO_CONTACT_30D" (payments with no contact at all in 30 days).
    nc = next(r for r in attr if r["channel"] == "NO_CONTACT_30D")
    # Real result: 10,793 payments = 63.8% had no contact: "self-cure" (the borrower paid without being chased).
    f["B_attribution"] = {
        "payments_with_no_contact_in_prior_30_days": nc["payments"],
        "share_pct": nc["share_of_payments_pct"],
        "verdict": "Most payments had no contact on any channel in the 30 days before; campaign-level "
                   "joins without a time window credit campaigns with these self-cure payments.",
    }
    # Check C (time zones): count calls per timezone value in the RAW calls table. Real result: about 30,400 each for
    # Asia/Dubai, Asia/Kolkata and UTC, so one third of the calls each. sql_repo/03 converts them all to UTC.
    f["C_timezones"] = {"calls_by_timezone": rows(con, "SELECT timezone, COUNT(*) calls FROM calls GROUP BY 1 ORDER BY 1"),
                        "verdict": "Calls are stored in local time for three zones; stg_calls converts to UTC."}
    # Check D (disposition codes). A disposition = the outcome code an agent records after a call (PTP, PAID, ...).
    # PTP = promise to pay. "codes": rows using PTP vs PROMISE_TO_PAY (real: 3,904 vs 3,926: two names for one thing,
    # so counting only one misses about half of 7,830 promises). "versions_with_both_codes": in how many schema
    # versions PROMISE_TO_PAY appears (real: 3 = legacy, v1 and v2, i.e. all of them).
    # raw_rows vs distinct_calls: 35,000 rows for 28,971 calls, so some calls carry more than one disposition.
    f["D_dispositions"] = {
        "codes": rows(con, """SELECT disposition_code, COUNT(*) n FROM call_dispositions
                              WHERE disposition_code IN ('PTP','PROMISE_TO_PAY') GROUP BY 1 ORDER BY 1"""),
        "versions_with_both_codes": one(con, """SELECT COUNT(DISTINCT disposition_version) FROM call_dispositions
                                               WHERE disposition_code = 'PROMISE_TO_PAY'""")[0],
        "raw_rows": one(con, "SELECT COUNT(*) FROM call_dispositions")[0],
        "distinct_calls": one(con, "SELECT COUNT(DISTINCT call_id) FROM call_dispositions")[0],
        "verdict": "PTP and PROMISE_TO_PAY both occur in every schema version; counting one misses about half of promises.",
    }
    # Check E (agents): from stg_agents (sql_repo/02), count agent_ids, how many have conflicting attributes
    # (attributes_unreliable = TRUE), and the average number of employee codes seen per id. [0] = the single row.
    # Real result: 1,000 agent_ids, all 1,000 conflicting, 29.6 employee codes per id on average.
    f["E_agents"] = rows(con, "SELECT * FROM (SELECT COUNT(*) agent_ids, SUM(CASE WHEN attributes_unreliable THEN 1 ELSE 0 END) conflicting, ROUND(AVG(employee_codes_seen),1) avg_codes FROM stg_agents)")[0]
    # Only 10 different names exist in the whole agents table (for 1,000 ids), so names cannot identify people.
    f["E_agents"]["distinct_names_in_table"] = one(con, "SELECT COUNT(DISTINCT agent_name) FROM agents")[0]
    # Add the plain-words verdict to the Check E dict.
    f["E_agents"]["verdict"] = ("Agent master data is inconsistent (codes and names change per row); "
                                "agent_id is used as the key and no per-person claims are made.")
    # Check F (portfolio mix): each month, what share of successful payments came from early accounts (dpd <= 30) and
    # from late accounts (dpd > 90)? DPD = days past due (how many days late the borrower is).
    # AVG(CASE WHEN ... THEN 1 ELSE 0 END) = the share of rows that meet the condition (the average of 1s and 0s).
    # JOIN accounts a USING (account_id) brings in each payment's account row, so its dpd can be read.
    # Real result: the early share stays between 44.1% and 47.2% every month, so the mix did not shift.
    f["F_portfolio_mix"] = rows(con, """
        SELECT strftime(p.event_at, '%Y-%m') AS month,
               ROUND(100.0 * AVG(CASE WHEN a.dpd <= 30 THEN 1 ELSE 0 END), 1) AS early_dpd_share_pct,
               ROUND(100.0 * AVG(CASE WHEN a.dpd > 90 THEN 1 ELSE 0 END), 1) AS late_dpd_share_pct
        FROM stg_recovery p JOIN accounts a USING (account_id)
        WHERE p.event_at < DATE '2026-08-01' GROUP BY 1 ORDER BY 1""")

    # Read the monthly metrics table (built by sql_repo/05, one row per month Jan-Jul) into a pandas DataFrame.
    metrics = con.execute("SELECT * FROM golden_monthly_metrics").fetchdf()
    # MoM = month-on-month change. pct_change() = (this month - last month) / last month, row by row; * 100 = percent;
    # round(1) = 1 decimal place. January has no previous month, so its value is empty (NaN = "not a number").
    # Real result: Feb -9.1, Mar +11.0, Apr -7.3, May +5.2, Jun -4.7, Jul +6.7.
    metrics["mom_recovery_pct"] = (metrics["total_recovery_inr"].pct_change() * 100).round(1)
    # Headline numbers. iloc[0] = first row (January), iloc[-1] = last row (July). metrics.loc[condition, column] picks
    # the March or February value. .iloc[1:] skips January's empty value before averaging Feb-Jul. float(...) turns a
    # numpy number into a plain Python number for JSON.
    # Real result: Jan 18.72, Jul 18.72, Mar +11.0, Feb -9.1, average +0.3 -> flat; the "+11%" was one rebound month.
    f["headline"] = {
        "jan_recovery_cr": float(metrics.iloc[0]["total_recovery_cr"]),
        "jul_recovery_cr": float(metrics.iloc[-1]["total_recovery_cr"]),
        "mar_mom_pct": float(metrics.loc[metrics["month"] == "2026-03", "mom_recovery_pct"].iloc[0]),
        "feb_mom_pct": float(metrics.loc[metrics["month"] == "2026-02", "mom_recovery_pct"].iloc[0]),
        "mean_mom_feb_to_jul_pct": round(float(metrics["mom_recovery_pct"].iloc[1:].mean()), 1),
        "verdict": "Recovery is flat Jan-Jul. The +11% is March alone, rebounding from a -9.1% February; not a trend.",
    }
    # Keep the full attribution table and the lift table (both from sql_repo/06) in f as well.
    f["channel_attribution"] = attr
    f["channel_lift"] = rows(con, "SELECT * FROM channel_lift")
    # DiD (difference-in-differences, sql_repo/08): store the 4 group rows, then compute the estimate in SQL:
    # (Field POST - Field PRE) - (Digital POST - Digital PRE). MAX(CASE WHEN ... END) pulls out the single value of one
    # group+period: CASE gives NULL for every other row and MAX ignores NULLs.
    # Real result: (8.20 - 7.22) - (7.32 - 7.68) = 0.98 + 0.36 = 1.34 percentage points.
    f["did"] = {"groups": rows(con, "SELECT * FROM did_results"),
                "estimate_pp": one(con, """SELECT ROUND(
                    (MAX(CASE WHEN grp='TREATMENT_FIELD' AND period='POST' THEN paid_within_30d_pct END)
                   - MAX(CASE WHEN grp='TREATMENT_FIELD' AND period='PRE'  THEN paid_within_30d_pct END))
                  - (MAX(CASE WHEN grp='CONTROL_DIGITAL' AND period='POST' THEN paid_within_30d_pct END)
                   - MAX(CASE WHEN grp='CONTROL_DIGITAL' AND period='PRE'  THEN paid_within_30d_pct END)), 2)
                   FROM did_results""")[0]}

    # 95% confidence intervals (normal approximation) so small differences
    # are not read as effects.
    # A 95% confidence interval (CI) = a range that, with 95% confidence, holds the true value. If the range includes 0,
    # the data cannot tell the effect apart from "no effect". pp = percentage points: 8.20% vs 7.22% is 0.98 pp apart.
    # Loop over the 4 channels in channel_lift and give each one a CI for its lift.
    for r in f["channel_lift"]:
        # p_ = the paid-within-30-days share as a fraction (7.92% -> 0.0792); n_ = accounts reached (14,827 for FIELD).
        p_, n_ = r["paid_within_30d_pct"] / 100, r["accounts_reached"]
        # se = standard error = how much a share would wobble from one sample to another: sqrt(p * (1 - p) / n), and
        # * 100 to put it in percentage points (** 0.5 = square root). Only the channel's own sample error is used;
        # the 7.7% baseline is treated as a fixed number.
        se = (p_ * (1 - p_) / n_) ** 0.5 * 100
        # 1.96 = the number of standard errors that covers the middle 95% of a normal ("bell curve") distribution.
        # CI = lift - 1.96 * se to lift + 1.96 * se. Real result: FIELD 0.23 pp -> [-0.2, 0.66]; every channel's CI includes 0.
        r["lift_ci95_pp"] = [round(r["lift_pp"] - 1.96 * se, 2), round(r["lift_pp"] + 1.96 * se, 2)]
    # g = the 4 DiD rows keyed by (group, period). Example: g[("TREATMENT_FIELD", "POST")] = the Field post row.
    g = {(r["grp"], r["period"]): r for r in f["did"]["groups"]}
    # The DiD estimate is built from 4 separate shares, so its variance (spread squared) is the SUM of their 4
    # variances p * (1 - p) / n. Start at 0.0 and add each one in the loop.
    var = 0.0
    # Loop over the 4 (group, period) keys.
    for key in g:
        # p_ = this group's paid share as a fraction, n_ = its number of targeting rows (e.g. 2,816 for Field POST).
        p_, n_ = g[key]["paid_within_30d_pct"] / 100, g[key]["targeting_rows"]
        # Add this group's variance to the total.
        var += p_ * (1 - p_) / n_
    # Standard error = square root of the total variance, * 100 for percentage points.
    se = var ** 0.5 * 100
    # est = the DiD estimate computed above (1.34 pp).
    est = f["did"]["estimate_pp"]
    # Real result: 1.34 -/+ 1.96 * se = [-0.25, 2.93]. It includes 0 -> no detectable effect of the April shift.
    f["did"]["ci95_pp"] = [round(est - 1.96 * se, 2), round(est + 1.96 * se, 2)]
    # Honest caveat stored with the result: one account can appear in many targeting rows, so the rows are not
    # independent and the true interval is probably wider.
    f["did"]["note"] = ("Rows are targeting events, not independent accounts, so the interval is if anything "
                        "too narrow. An interval that includes 0 means no detectable effect.")

    # Write f to forensics_summary.json. indent=2 = a readable layout; default=str = anything json cannot write by itself
    # (like a date) is written as text. "with open(...)" closes the file automatically at the end of the block.
    with open("forensics_summary.json", "w", encoding="utf-8") as fh:
        json.dump(f, fh, indent=2, default=str)

    # 4. exports
    # golden_metrics.csv = the monthly table, now including the mom_recovery_pct column. index=False = no extra
    # row-number column in the file.
    metrics.to_csv("golden_metrics.csv", index=False)
    # Make the results/ folder; exist_ok=True = no error if it already exists.
    os.makedirs("results", exist_ok=True)
    # Save the 3 result tables as CSV files: results/channel_attribution.csv, results/channel_lift.csv,
    # results/did_results.csv.
    for t in ("channel_attribution", "channel_lift", "did_results"):
        con.execute(f"SELECT * FROM {t}").fetchdf().to_csv(f"results/{t}.csv", index=False)
    # dashboard/data.json = one bundle of the main numbers. fillna(0) writes January's empty MoM value as 0.
    # The "forensics" part keeps only keys that start with A_, B_, D_, E_ or "headline" (C and F are left out).
    # Note: dashboard/index.html does not read data.json; the page has its numbers typed in by hand.
    dashboard = {
        "monthly_metrics": json.loads(metrics.fillna(0).to_json(orient="records")),
        "channel_attribution": attr,
        "channel_lift": f["channel_lift"],
        "forensics": {k: v for k, v in f.items() if k.startswith(("A_", "B_", "D_", "E_", "headline"))},
        "did": f["did"],
    }
    # Write the bundle with the same JSON settings as above.
    with open("dashboard/data.json", "w", encoding="utf-8") as fh:
        json.dump(dashboard, fh, indent=2, default=str)

    # Print the main monthly columns so a run can be checked by eye. to_string(index=False) = a plain text table.
    print("\nMonthly metrics:\n", metrics[["month", "total_recovery_cr", "mom_recovery_pct", "paying_account_rate_pct",
                                          "answer_rate_pct", "rpc_rate_pct", "ptp_kept_rate_pct",
                                          "recovery_per_agent_hour_inr"]].to_string(index=False))
    # Print the channel attribution, lift and DiD tables, the DiD estimate with its CI, and the lift CIs.
    print("\nChannel attribution:\n", con.execute("SELECT * FROM channel_attribution").fetchdf().to_string(index=False))
    print("\nChannel lift:\n", con.execute("SELECT * FROM channel_lift").fetchdf().to_string(index=False))
    print("\nDiD:\n", con.execute("SELECT * FROM did_results").fetchdf().to_string(index=False), "\nestimate_pp =", f["did"]["estimate_pp"], "ci95 =", f["did"]["ci95_pp"])
    print("Lift CIs:", [(r["channel"], r["lift_pp"], r["lift_ci95_pp"]) for r in f["channel_lift"]])
    # Print the Check A numbers, leaving out the long month-by-month list and the verdict text.
    print("\nDuplicates:", {k: v for k, v in f["A_duplicate_payments"].items() if k not in ("old_reference_dedup_by_month", "verdict")})
    # Close the database connection.
    con.close()


# This block runs only when the file is started directly ("python run_pipeline.py"), not when another file
# imports it: __name__ equals "__main__" only in the first case.
if __name__ == "__main__":
    main()
