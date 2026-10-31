# Install

combu needs **PostgreSQL 18** (temporal keys) with **PostGIS** and **btree_gist** available. It is pure SQL, so there is nothing to compile: installing it means putting two kinds of file in PostgreSQL's extension directory, then running `CREATE EXTENSION` in a database.

## Docker

The repository's image is `timescale/timescaledb-ha` (PostgreSQL 18 with TimescaleDB and PostGIS) with combu added:

```bash
docker build -f docker/Dockerfile -t combu .
docker run -d --name combu -e POSTGRES_PASSWORD=secret -p 5432:5432 combu
```

To use another base image, pass `--build-arg BASE=<image>`. It must have PostgreSQL 18 and PostGIS.

## From source

On the database server, with `pg_config` for the target PostgreSQL on the `PATH`:

```bash
make install          # copies combu.control and sql/combu--*.sql into $(pg_config --sharedir)/extension
```

## In a database

```sql
CREATE EXTENSION combu CASCADE;    -- also installs btree_gist and postgis if needed
SELECT extversion FROM pg_extension WHERE extname = 'combu';
```

This creates two schemas:

- `registry` holds the tables, functions and triggers.
- `asof` holds the point-in-time views generated from the catalog.

Extensions that combu requires keep their own schemas (PostGIS goes in `public` by default).

From Python, `combu install --url …` (combu-py) does the same, or updates an older version.

## Updating

Install the new release's files on the server, then in each database:

```sql
ALTER EXTENSION combu UPDATE;      -- runs every upgrade script from the installed version
```

Upgrades only go forward. Read the release notes before a minor version while combu is below 1.0.

## Managed databases

Services such as Amazon RDS, Cloud SQL, Azure Database or Supabase only allow extensions from their own list, and you can't copy files to their servers. Support through **pg_tle** (Trusted Language Extensions, which installs a SQL extension through SQL) is planned. Until then, combu needs a server where you control the extension directory: your own, a VM or a container.

## Removing

```sql
DROP EXTENSION combu CASCADE;
```

!!! danger
    This drops the `registry` and `asof` schemas with **all the data in them**, and anything that depends on them. Back up first ([Backups](backups.md)).
