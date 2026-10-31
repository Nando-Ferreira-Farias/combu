# 0003: combu, a database core in SQL with thin clients and extensions

- **Status:** Accepted. Its migration mechanism (SQL files, a version table and a runner) is superseded by [decision 0004](0004-postgres-extension.md).
- **Date:** 2026-10-31
- **Origin:** ADR 0007 of the summary project, where combu started.

## Context

The entity registry ([decision 0001](0001-temporal-entity-registry.md), [0002](0002-several-sources-per-fact.md), and summary's ADR 0005) doesn't depend on the data it holds. Its core knows no subject, and themes add the subjects. It should outlive this project: a later rewrite of summary, or another project, should be able to reuse it, possibly in another language. Time series and other layers will join it.

Today its logic is split between two places:

| Part | Lives in |
|---|---|
| Temporal keys and foreign keys, type and rule triggers, cycle check, hierarchy functions, `as_of()` | PostgreSQL |
| Sync (diff, claims, lifetime union, apply), `asof` view generation, the catalog of themes, migrations (Alembic), TSV parsing and validation, CLI, queries | Python, inside `summary` |

Only the PostgreSQL part can be reused from another language. Moving the core to a separate service (an HTTP API or a program in another language) would put a process between the data and its users. That loses what makes the design valuable: SQL joins with time series, point-in-time views, and atomic syncs inside one transaction.

## Decision

The database logic becomes a project of its own, **combu**, organised in layers. Its core is written in SQL.

- **combu-db, the core.** It is a PostgreSQL schema with its rules: entities, claims, types, hierarchies, aliases, geometry, datasets and priorities, and later time series. **Every rule that defines correct data lives in the database.** combu-db has two contracts:
    - **The database contract.** Tables, constraints, views and functions are its public interface, usable from any language that speaks SQL.
    - **The data contract.** A specification of a dataset's desired state (entities, claims, facts, periods) and of the rules for applying it. The TSV folder format is one serialisation of it.
- **The core logic moves into PostgreSQL:**
    - **Sync** becomes a function over staging tables. A client bulk-loads a dataset's desired state (`COPY`), calls the sync function, and gets back the plan it applied. A dry run is the same call in a transaction that is rolled back.
    - **View generation** becomes a SQL procedure that reads the catalog. The `asof` views and type-check triggers stay derived, never hand-written.
    - **The catalog is data.** Entity types, hierarchies, rules and code lists live only in the database. An extension inserts them in its migration, and no client keeps a second copy.
    - **Migrations are plain, ordered SQL files** with their version recorded in the database, applied by a small runner. Alembic stays an application's tool for its own objects, not the core's. combu-db may later be packaged as a PostgreSQL extension (`CREATE EXTENSION combu`).
- **Clients are thin.** A client connects, parses files (TSV, source formats) into the data contract, stages them, calls the core's functions and presents results. It may validate files offline for convenience, but the database is the authority. **combu-py**, the Python client with the CLI, is the first; it's what the current `summary.registry` code becomes.
- **Extensions are of two kinds:**
    - **Domain extensions** add structure in the same form as the core: SQL migrations with catalog rows, tables and functions. Geography and the electrical system are domain extensions of combu, not part of summary. Time series is one too.
    - **Interface extensions** add ways in or out: combu-api (an HTTP service), loader helpers, and later others. They are clients of the core.
- **Applications use combu.** summary keeps its data (`data/registry/`), its loaders, its API and its dashboard. It requires a combu-db version and reaches the core through combu-py.
- **The contracts are versioned.** combu-db follows semantic versioning. Removing or changing anything in the database or data contract is a major version. Extensions declare the core version they need.
- **One repository, for now.** combu is developed in this repository under `combu/` (`combu-db`, `combu-py`, the domain extensions), and summary uses it as a workspace dependency. It moves to its own repository, with its history (`git subtree split`), once the core is stable: the electrical extension built and time series designed.

## Consequences

- The core can be reused from any language and survives a rewrite of summary. Another client only needs the thin layer: staging, calling functions, presenting results.
- **Sync becomes set-based in SQL**, which is also the bulk path the loaders needed.
- **PL/pgSQL is harder to write, debug and test than Python.**
    - The core's tests run against a real database: through combu-py's integration suite, which already does, and SQL-level tests where useful.
    - The test-only theme becomes a test-only domain extension.
- **Alembic autogenerate no longer writes the core's migrations**, so core migrations are written by hand. `summary.db.temporal` (SQLAlchemy support for temporal keys) stays useful only for clients that map the core's tables with an ORM.
- **The move is incremental.** Each step keeps everything working, and the Python code turns into the client as its logic moves to SQL:
    1. The `combu/` layout and the SQL migration runner. The current core migrations become combu-db's first version.
    2. The catalog as data only.
    3. Sync over staging tables.
    4. View generation in SQL.
    5. Geography and electrical as domain extensions.
- Decisions 0001 and 0002 (and summary's ADR 0005) still hold. This decision changes where they are implemented. "One write path" now means the core's sync function, which every client calls.
