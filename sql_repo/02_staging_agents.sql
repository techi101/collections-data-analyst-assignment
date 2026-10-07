-- ============================================================
-- 02_staging_agents.sql
-- Agent master data: one row per agent_id.
--
-- Finding: the agents table cannot be used for identity resolution.
--   30,000 rows, 1,000 agent_ids, 1,099 employee_codes, only 10 names.
--   Every agent_id appears on ~30 rows, and employee_code, name and team
--   change from row to row (e.g. AGT0000001 is five different people in
--   its first five rows). Grouping by name, as the first version did,
--   merged 1,000 ids into 10 "agents"; that was an artefact, not a finding.
--
-- Decision: agent_id is the key (it is what calls, dispositions and
-- sessions use). Attributes come from the most recently updated row and
-- are flagged as unreliable.
-- ============================================================

-- WHAT THIS FILE IS: the clean-up of the staff register. Picture an attendance register where the same badge number
-- (agent_id) shows a different person's name on almost every page. You cannot trust the names, so you keep the badge
-- number as the ID, note only the latest name, and put a warning sticker on it saying "unreliable".
-- Real example: the agents table has 30,000 rows for 1,000 agent_ids, 1,099 employee_codes and only 10 names.
-- AGT0000001's rows say EMP01065 "Neha Singh", then EMP00285 "Sneha Das", then EMP00113 "Amit Kumar".
-- THE TRAP (August version): grouping by agent_name merged the 1,000 ids into 10 fake "agents" and produced a
-- "productivity fell 25%" story. Corrected: agent_id is the key, no per-person claims are made, and productivity
-- is flat at Rs 16,117-17,008 per agent-hour (file 05).
-- Overall flow: agents (raw history rows) -> rank each agent_id's rows newest first + count its codes and names
--   -> keep the newest row per agent_id -> flag ids whose code or name ever changed -> stg_agents (1,000 rows).
--
-- Start clean: delete stg_agents if an earlier run made it.
DROP TABLE IF EXISTS stg_agents;
-- Make the stored table stg_agents from the query below.
CREATE TABLE stg_agents AS
-- CTE "ranked": every raw agents row plus 4 helper columns, each worked out per agent_id.
WITH ranked AS (
    SELECT *,
        -- Window function: number the rows of each agent_id 1, 2, 3 ... with the NEWEST updated_at first
        -- (DESC = descending = biggest/latest first). So rn = 1 is the most recently updated row.
        ROW_NUMBER() OVER (PARTITION BY agent_id ORDER BY updated_at DESC) AS rn,
        -- history_rows = how many rows this agent_id has in total (about 30 each).
        COUNT(*)                      OVER (PARTITION BY agent_id) AS history_rows,
        -- COUNT(DISTINCT x) = how many DIFFERENT values of x. employee_codes_seen = different employee codes under one id
        -- (29.6 on average). A clean master table would show exactly 1.
        COUNT(DISTINCT employee_code) OVER (PARTITION BY agent_id) AS employee_codes_seen,
        -- names_seen = different names under one id.
        COUNT(DISTINCT agent_name)    OVER (PARTITION BY agent_id) AS names_seen
    -- Read the raw agents table.
    FROM agents
)
-- Main SELECT: keep the id, rename the newest row's attributes with a "latest_" prefix (AS = new column name),
-- and keep the counts from the CTE.
SELECT agent_id, employee_code AS latest_employee_code, agent_name AS latest_name,
       team AS latest_team, status AS latest_status, updated_at,
       history_rows, employee_codes_seen, names_seen,
       -- A true/false (boolean) column: TRUE if the id ever had more than one employee code OR more than one name.
       -- Real result: TRUE for all 1,000 agent_ids.
       (employee_codes_seen > 1 OR names_seen > 1) AS attributes_unreliable
-- Read from the CTE and keep only the newest row of each agent_id (rn = 1), so exactly one row per agent_id.
FROM ranked WHERE rn = 1;

-- Audit query (result not saved): number of ids, how many are flagged, and the average codes per id.
-- SUM(CASE WHEN flag THEN 1 ELSE 0 END) counts the TRUE rows. AVG = average. ROUND(..., 1) = 1 decimal.
-- Real result: 1,000 ids, 1,000 flagged, 29.6 codes per id.
SELECT COUNT(*) AS agent_ids,
       SUM(CASE WHEN attributes_unreliable THEN 1 ELSE 0 END) AS with_conflicting_attributes,
       ROUND(AVG(employee_codes_seen), 1) AS avg_employee_codes_per_id
FROM stg_agents;
