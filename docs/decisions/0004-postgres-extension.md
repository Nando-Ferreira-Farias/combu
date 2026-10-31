# 0004: combu ships as a PostgreSQL extension, in its own repository

- **Status:** Accepted
- **Date:** 2026-10-31
- **Origin:** ADR 0008 of the summary project, where combu started.

## Context

[decision 0003](0003-sql-core.md) moved the registry's logic into a SQL core, combu-db. Its first step shipped the core as numbered SQL files, applied by a small runner of our own that recorded them in `combu.migration`.

PostgreSQL already has a standard way to ship SQL that others install: **extensions**. PostGIS is one, with its own repository, releases and documentation site. With an extension, PostgreSQL itself tracks what is installed (`pg_extension`), installs dependencies (`CREATE EXTENSION ... CASCADE`) and chains upgrade scripts (`ALTER EXTENSION ... UPDATE`). An extension is usable from any language without a combu client.

## Decision

- **combu is a PostgreSQL extension named `combu`.** It consists of:
    - **Files:** a control file (`combu.control`), one install script per release (`combu--0.1.0.sql`) and upgrade scripts between releases (`combu--0.1.0--0.2.0.sql`).
    - **Requirements:** `btree_gist` and `postgis`. The extension isn't relocatable, and it creates the `registry` and `asof` schemas.
    - **Building:** it's pure SQL and PL/pgSQL with nothing to compile. A PGXS `Makefile` installs it (`make install`) and runs its regression tests (`make installcheck`).
    - **Versions:** semantic versioning, with forward-only upgrades. Removing or changing anything in the database or data contract is a major version.
- **Backups keep the data.** `pg_dump` doesn't dump data in an extension's tables unless they are registered. Every table that holds data, and its identity sequence, is marked with `pg_extension_config_dump`. A test restores a dump and compares it with the original. A table without the mark fails review.
- **Derived objects aren't extension members.** The `asof` views and type-check triggers are rebuilt from the catalog, by the client until decision 0003's step 4 and by a core function after it. `DROP EXTENSION combu` therefore needs `CASCADE`, and that also drops the data, as with PostGIS.
- **Domain extensions are extensions too.** Geography and the electrical system become `combu_geo` and `combu_power`, each with `requires = 'combu'`, as `postgis_topology` requires `postgis`.
- **Step 1's runner and `combu.migration` are retired.** combu-py installs and updates the extension (`CREATE EXTENSION IF NOT EXISTS combu CASCADE`, `ALTER EXTENSION combu UPDATE`) and reports the installed and available versions.
- **combu is distributed four ways:**
    - **GitHub:** the source repository, with versioned releases.
    - **Docker:** an image based on `timescale/timescaledb-ha` with combu installed.
    - **PGXN:** the PostgreSQL extension network.
    - **pg_tle:** for managed databases that refuse extension files (RDS, Aurora; Supabase's database.dev is built on it). This one comes later.
- **The documentation is a site of its own**, built with Zensical and served from GitHub Pages: install, data model, SQL reference, data contract, upgrades and clients.
- **There are two repositories:**
    - **combu**: the extension, its tests, the docs site, the Docker image, and combu-py under `clients/python/`. The client stays there while the SQL and the client change together; it moves out once it's stable or a second client language appears.
    - **summary**: the application.
- **summary switches when combu is published.** It will run the combu image, take combu-py from its published package, and have its Alembic environment ensure the extension is installed and up to date before its own migrations. Until then, summary's `combu/` directory is a frozen copy, and changes to the core go to the combu repository.

## Consequences

- This supersedes decision 0003's migration mechanism: the SQL files with a version table, and the runner. Everything else in decision 0003 stands.
- **Installing combu needs files on the database server**, so on managed services it depends on pg_tle or on the provider. Docker and self-hosted servers have no such limit.
- Every core change becomes an upgrade script plus, at release, a new full install script. The regression tests install the latest version directly and also upgrade from the previous one, and both must give the same schema.
- Backups are safe only while every data table is registered for dumping. The dump-and-restore test guards this.
- summary briefly carries a frozen copy of combu, until it switches to the published release.
