-- CREATE EXTENSION installs the requirements and creates the registry and asof schemas.
SET client_min_messages = warning;
CREATE EXTENSION combu CASCADE;
SELECT extversion FROM pg_extension WHERE extname = 'combu';
SELECT extname FROM pg_extension WHERE extname IN ('btree_gist', 'postgis') ORDER BY 1;
SELECT nspname FROM pg_namespace WHERE nspname IN ('registry', 'asof') ORDER BY 1;
SELECT tablename FROM pg_tables WHERE schemaname = 'registry' ORDER BY 1;
SELECT p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'registry' ORDER BY 1;
