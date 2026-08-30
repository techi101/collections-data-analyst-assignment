# Data Quality Report

As part of the assignment, I performed extensive data forensics on the 17 raw tables. The datasets contained intentional quality issues that significantly impact metrics if not addressed.

## Key Findings & Treatment

### A. Duplicate Payments
- **Detection**: Found 3,746 duplicate `payment_reference` values in the `payments` table. These look like retry events or ingestion errors.
- **Impact**: Calculating recovery purely on the raw `payments` table artificially inflates the recovery rate and the reported 11% improvement.
- **Treatment**: We deduplicated payments by keeping only one record per `payment_reference` (taking the earliest `event_at`).

### B. Timezone Mismatches
- **Detection**: Found 60,887 calls where the `calls.timezone` does not match the `accounts.timezone` or standard UTC. The dataset explicitly contains UTC, Asia/Kolkata, and Asia/Dubai timestamps.
- **Impact**: Grouping calls by hour or day (e.g., for "attempt frequency" or "contact rate by hour") will be completely wrong, leading to false conclusions about when borrowers are most responsive.
- **Treatment**: The Golden Dataset pipeline standardizes all timestamps across all tables to UTC before joining.

### C. Agent Identity Problems
- **Detection**: Found 10 distinct `agent_name`s that map to multiple `agent_id`s in the `agents` table.
- **Impact**: Evaluating "recovery per agent-hour" or analyzing top-performing agents will be skewed because a single human is split across multiple IDs.
- **Treatment**: We created a master agent mapping, grouping by `agent_name` (or `employee_code`) and assigning a single canonical `agent_id`.

### D. Duplicate Borrowers
- **Detection**: Found 8,566 duplicate `borrower_id`s in the `borrowers` table.
- **Impact**: Joins on `borrower_id` would multiply rows, exploding metrics downstream.
- **Treatment**: Deduplicated `borrowers` by selecting the most recently updated record (using `updated_at`).

### E. Legacy Schema & Disposition Codes
- **Detection**: The `vendor_telephony` and `call_dispositions` tables reference `schema_version` and `disposition_version`. Older versions have different status mappings.
- **Impact**: If older "Promise to Pay" or "Contacted" codes are missed, our Contact Rate and PTP Rate will be artificially low.
- **Treatment**: We normalized disposition codes by mapping legacy codes to a standardized modern schema in our `dim_dispositions` golden table.

> [!WARNING]
> Because these issues existed, the raw data cannot be trusted. All subsequent analyses in this assignment use the **Golden Dataset** built through our reproducible pipeline.
