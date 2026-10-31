-- Every table and sequence in the registry schema is registered with pg_extension_config_dump,
-- so pg_dump keeps its data. A new table that isn't shows up in the second query.
SELECT cardinality(extconfig) AS registered FROM pg_extension WHERE extname = 'combu';
SELECT c.relname AS not_registered
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'registry' AND c.relkind IN ('r', 'S')
  AND c.oid <> ALL (SELECT unnest(extconfig) FROM pg_extension WHERE extname = 'combu')
ORDER BY 1;
