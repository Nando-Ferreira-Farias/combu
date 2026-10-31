-- One line per table in the registry schema: row count and a checksum of its rows.
SELECT format(
  'SELECT %L AS tbl, count(*) AS n, md5(coalesce(string_agg(x::text, %L ORDER BY x::text), %L)) '
  'FROM registry.%I x', c.relname, '|', '', c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'registry' AND c.relkind = 'r' ORDER BY c.relname
\gexec
