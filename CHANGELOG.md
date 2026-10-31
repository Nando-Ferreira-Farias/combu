# Changelog

combu follows semantic versioning; until 1.0, a minor version may change the contracts.

## 0.1.0 (unreleased)

First version as a PostgreSQL extension. It was extracted from the summary project, where the
registry started.

- The `registry` schema: datasets with priorities, entity types, entities and their claims,
  hierarchies with rules and temporal edges, aliases and geometry. The `asof` schema for
  generated point-in-time views.
- Temporal keys on every fact (PostgreSQL 18 `WITHOUT OVERLAPS` and `PERIOD`), with the owning
  dataset in every key but the alias key.
- Functions: `as_of` (setting `combu.as_of`), type lineage, and hierarchy functions that follow
  the highest-priority dataset at each instant.
- Triggers: no entities of abstract types, typed references (`require_type`), hierarchy rules
  and cycles.
- Every data table and identity sequence is registered for `pg_dump`.
- combu-py 0.1.0: installs, updates and inspects the extension (`combu install|status`).
- Released under the PostgreSQL License.
