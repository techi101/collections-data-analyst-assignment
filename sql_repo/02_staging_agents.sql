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

DROP TABLE IF EXISTS stg_agents;
CREATE TABLE stg_agents AS
WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY agent_id ORDER BY updated_at DESC) AS rn,
        COUNT(*)                      OVER (PARTITION BY agent_id) AS history_rows,
        COUNT(DISTINCT employee_code) OVER (PARTITION BY agent_id) AS employee_codes_seen,
        COUNT(DISTINCT agent_name)    OVER (PARTITION BY agent_id) AS names_seen
    FROM agents
)
SELECT agent_id, employee_code AS latest_employee_code, agent_name AS latest_name,
       team AS latest_team, status AS latest_status, updated_at,
       history_rows, employee_codes_seen, names_seen,
       (employee_codes_seen > 1 OR names_seen > 1) AS attributes_unreliable
FROM ranked WHERE rn = 1;

SELECT COUNT(*) AS agent_ids,
       SUM(CASE WHEN attributes_unreliable THEN 1 ELSE 0 END) AS with_conflicting_attributes,
       ROUND(AVG(employee_codes_seen), 1) AS avg_employee_codes_per_id
FROM stg_agents;
