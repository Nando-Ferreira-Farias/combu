# Development

## Layout

```text
combu.control                  extension metadata: default version, requirements
sql/combu--X.Y.Z.sql           full install script of each release
sql/combu--X.Y.Z--A.B.C.sql    upgrade script between consecutive releases
test/sql/, test/expected/      pg_regress tests (make installcheck)
test/dump/                     dump-and-restore test (make dumpcheck)
docker/Dockerfile              PostgreSQL 18 + TimescaleDB + PostGIS + combu
clients/python/                combu-py
docs/, zensical.toml           this site
```

## A server to work against

```bash
docker build -f docker/Dockerfile -t combu:dev .
docker run -d --name combu-dev -e POSTGRES_PASSWORD=secret -p 127.0.0.1:55432:5432 \
  -v "$PWD":/combu combu:dev
docker exec -u root combu-dev bash -c 'apt-get update -qq && apt-get install -y -qq make'
```

After changing SQL, reinstall the files in the container. There, run the tests as the `postgres` user:

```bash
docker exec -u root -w /combu combu-dev make install
docker exec -w /combu combu-dev make installcheck PGUSER=postgres
docker exec -w /combu -e PGUSER=postgres combu-dev make dumpcheck
```

Python client: `cd clients/python && uv run ruff check . && uv run mypy && DATABASE_URL=postgresql+psycopg://postgres:secret@localhost:55432/postgres uv run pytest`.

Docs: `uvx zensical==0.0.70 build --strict`.

## Regression tests

Each file in `test/sql/` runs in a fresh database, and its output must match `test/expected/` exactly. When a change alters the output on purpose:

1. Run `make installcheck`.
2. Read `test/results/<name>.out` and check that it is right.
3. Copy it to `test/expected/`.

Never accept an output you haven't read.

## Changing the extension

combu follows semantic versioning. Until 1.0, a minor version may change the contracts, and release notes say how.

1. **Work on an upgrade script** from the last release: `sql/combu--0.1.0--0.2.0.sql`. Released scripts are never edited.
2. **New tables that hold data** get `pg_catalog.pg_extension_config_dump('registry.<table>', '')`, and so does their identity sequence. Otherwise `config_dump` fails and backups would lose them ([Backups](backups.md)).
3. **Qualify every name** (`registry.entity`, `pg_catalog.…`), and reach PostGIS through `@extschema:postgis@`.
4. **At release:**
    - Write the full install script `sql/combu--0.2.0.sql`: the previous install script plus the upgrade.
    - Set `default_version` in `combu.control`.
    - Bump combu-py if it changes.
    - Tag `v0.2.0`.
5. **Tests prove both paths** (from the second release on): a fresh install of the new version, and an update from the previous one, must give the same schema.

## Releases

A tag `vX.Y.Z` publishes:

- the extension files (a GitHub release)
- the Docker image
- combu-py

PGXN and pg_tle packaging come later ([roadmap](roadmap.md)).
