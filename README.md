# combu

A PostgreSQL extension for things that **change over time** and are **described by several sources**: entities with a permanent identity, hierarchies, aliases and geometry, where every fact has a validity period and every source keeps its own version.

```sql
CREATE EXTENSION combu CASCADE;        -- PostgreSQL 18, with btree_gist and postgis
SET combu.as_of = '2019-06-01';
SELECT * FROM registry.hierarchy_tree('admin');
```

**Status: 0.1.0, early.** The registry core is in place; time series, forecasts and scenarios are next.

## Install

```bash
make install                                         # on the server: copies the extension files
docker build -f docker/Dockerfile -t combu .         # or: TimescaleDB + PostGIS + combu
```

Then `CREATE EXTENSION combu CASCADE;` in a database. Restore backups in a single transaction (`pg_restore --single-transaction`); see [docs/backups.md](docs/backups.md).

## Repository

| Path | What |
|---|---|
| `combu.control`, `sql/` | the extension: control file, install and upgrade scripts |
| `test/` | regression tests (`make installcheck`) and the dump-and-restore test (`make dumpcheck`) |
| `docker/` | an image with combu installed |
| `clients/python/` | combu-py, the Python client |
| `docs/` | the documentation site (Zensical, published to GitHub Pages) |

Documentation: [docs/index.md](docs/index.md), with install, the data model, the SQL reference, backups, development and the decisions behind the design.
