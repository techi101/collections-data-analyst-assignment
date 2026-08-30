-- ============================================================
-- 02_staging_agents.sql
-- Entity resolution: same agent under multiple agent_ids
-- Source of truth: employee_code (payroll system)
-- Strategy: MIN(agent_id) as canonical ID per agent_name
-- ============================================================

DROP TABLE IF EXISTS stg_agents;
CREATE TABLE stg_agents AS
WITH canonical AS (
    SELECT 
        MIN(agent_id) AS canonical_agent_id,
        employee_code,
        agent_name,
        MIN(team) AS team,
        MIN(joined_at) AS joined_at,
        MAX(status) AS status,
        COUNT(DISTINCT agent_id) AS num_duplicate_ids
    FROM agents
    GROUP BY employee_code, agent_name
)
SELECT * FROM canonical;

-- Show how many agent IDs were collapsed
SELECT 
    'Agents before resolution' as metric, COUNT(DISTINCT agent_id) as value FROM agents
UNION ALL
SELECT 
    'Agents after resolution', COUNT(DISTINCT canonical_agent_id) FROM stg_agents
UNION ALL
SELECT 
    'Agents with identity conflicts', SUM(CASE WHEN num_duplicate_ids > 1 THEN 1 ELSE 0 END) FROM stg_agents;
