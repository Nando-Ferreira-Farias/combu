# 0001: Temporal entity registry on PostgreSQL 18

- **Status:** Accepted
- **Date:** 2026-10-31
- **Origin:** ADR 0004 of the summary project, where combu started.

## Context

The project needs one consistent way to store register data: countries, regions, communes, substations, buses, lines, plants, units, companies. It has to meet three requirements:

- **Any number of hierarchies.** Examples are country → region → province → commune, and country → system → substation → bus → unit.
- **Easy to evolve.** A type must be able to split into subtypes (`power_plant` into thermal and hydro), and attribute columns and hierarchy levels must be easy to add.
- **Point in time.** A study must see the system exactly as it was on any date, including changes such as the SIC–SING interconnection or Ñuble splitting from Biobío.

The first design (one table per asset kind, each holding its own foreign keys) couldn't cover all three at once. No asset tables existed yet, so it could be replaced at no cost.

## Decision

- **Every thing is an `entity`** whose `id` never changes. Hierarchies, aliases, geometry, relations and (later) time series reference `entity.id`, never a type-specific table.
- **Types form a tree** (`entity_type`). Abstract types group subtypes, so a query for a type covers its whole subtree.
- **Attributes live in typed tables, one per type, named after it** (class-table inheritance). There is no JSONB anywhere: an attribute either has a real column or isn't stored. A subtype's table holds only its extra columns.
- **Every fact has a validity period.** Valid time only, as a half-open `tstzrange`. Attribute versions, hierarchy edges, aliases, geometry and relations each have one, and the entity itself has a `lifetime`. There's no bitemporal history and no audit log; curated history lives in git (summary's ADR 0005 (curated data as code)). Each source keeps its own versions of a fact ([decision 0002](0002-several-sources-per-fact.md)).
- **Hierarchies are strict trees.** A child has one parent per hierarchy at any instant (per source; readers follow the highest-priority source). `hierarchy_rule` says which parent type may hold which child type. Anything that needs a second parent is a typed **relation** (`line_terminal`, `ownership`) or a separate hierarchy.
- **A core and themes.** The core (entities, types, hierarchies, aliases, geometry, datasets) knows no subject. Themes add entity types, hierarchies, code tables and typed tables, each with its own migration: geography first, the electrical system next.
- **In the electrical theme, units will connect to buses**, and a separate `plant_composition` hierarchy groups units into plants, because a plant's units can connect at different buses.
- **PostgreSQL 18 enforces the time rules** with `WITHOUT OVERLAPS` keys (no overlapping versions, one parent at a time) and `PERIOD` foreign keys (no fact outside its entity's lifetime). Triggers enforce type rules, typed references and acyclicity.
- **Point-in-time reads** go through generated views in the `asof` schema (`asof.commune`), filtered by `registry.as_of()` (the session setting `combu.as_of`). Functions such as `registry.hierarchy_tree`, `registry.entity_ancestor` and `registry.entity_descendants` take an explicit instant.
- **Nothing in `public`.** The registry's tables, functions and triggers live in the `registry` schema, and the generated views in `asof`. `public` keeps only the extensions and Alembic's version table, and later layers (time series, operations) get their own schemas.
- **Scenarios and planned projects are deferred.** The main tables describe reality only, so scenarios can later be added as an overlay without changing them.

## Consequences

- The database image moves to `timescaledb-ha:pg18.6-ts2.30.2`. The old PostgreSQL 17 volume had to be recreated (it held no data).
- SQLAlchemy has no syntax for temporal keys. `summary.db.temporal` provides constraint classes, renders them for Alembic autogenerate and patches foreign-key reflection to ignore `PERIOD`. That module may need care on SQLAlchemy upgrades. The integration tests run `alembic check`, so a problem shows up there.
- The views and type-check triggers are derived from the schema and rebuilt on every migration run, so they never appear in migrations. Adding a column needs no view change.
- Every hierarchy query has to name an instant. Plain dates in SQL are read in the session's timezone, so studies should `SET TIME ZONE 'America/Santiago'`.
- The design is documented in [Data model](../model.md), and the change procedures in summary's registry operations.
