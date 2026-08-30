-- 03_clean_agents.sql
-- Resolves agent identity conflicts where one agent has multiple vendor/system IDs.

DROP TABLE IF EXISTS clean_agents;
CREATE TABLE clean_agents AS
SELECT MIN(agent_id) as canonical_agent_id, agent_name, MIN(team) as team
FROM agents
GROUP BY agent_name;
