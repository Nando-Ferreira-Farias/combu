# combu-db

The core, as plain PostgreSQL 18 SQL. It needs PostgreSQL 18 (temporal keys), PostGIS and btree_gist; the first migration creates the two extensions.

## Migrations: the contract

Any runner in any language applies combu-db the same way. combu-py's runner (`combu migrate`, `combu.migrate`) is one implementation.

- **Components.** Each component is a directory: `core/` now, and later one per extension (`geography/`, ...). A runner applies the components a database needs, the core first.
- **Files.** `NNNN_short_name.sql`, numbered from `0001` without gaps. Each file is one migration, run as a whole (it may contain many statements and `$$`-quoted functions).
- **Bookkeeping.** Applied migrations are recorded in `combu.migration`, which the runner creates if missing:

  ```sql
  CREATE TABLE combu.migration (
    component  text NOT NULL,
    version    integer NOT NULL,
    name       text NOT NULL,
    checksum   text NOT NULL,      -- sha256 of the file's bytes (hex)
    applied_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (component, version));
  ```
- **Order and atomicity.** Pending migrations run in order inside one transaction, together with their `combu.migration` rows, under the advisory lock `pg_advisory_xact_lock(hashtext('combu.migrate'))`. A failure leaves nothing behind.
- **Forward-only.** A change is a new file. A runner refuses to continue if an applied file's checksum no longer matches, or if the database has a migration that isn't on disk.

Without any client, `psql` can apply a component by running each pending file in order and inserting its row into `combu.migration`.

## The core today

| File | Contents |
|---|---|
| `core/0001_registry_tables.sql` | the `registry` and `asof` schemas; datasets (with priority), entity types, entities and their claims, hierarchies, rules and edges, aliases, geometry |
| `core/0002_registry_functions.sql` | `registry.as_of()` (session setting `combu.as_of`), type and hierarchy functions, integrity triggers |

The data model is described in [docs/design/data-model.md](../../docs/design/data-model.md).

## Changing the core

1. Add the next file in `core/`. Never edit an applied one.
2. If a client maps the changed tables (`summary.models.core` does, with SQLAlchemy), update the mapping in the same change. In summary, `uv run alembic check` fails while the two disagree.
3. `just migrate` applies it, since summary's Alembic environment runs combu's runner first. Then run the tests: `just test-integration` builds fresh databases from these files.
