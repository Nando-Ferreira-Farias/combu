# combu

combu is a PostgreSQL extension for things that **change over time** and are **described by several sources**:

- power plants, regions or companies
- the hierarchies they belong to
- what each source says about them, and when

Each of them is an entity with a permanent identity. Every fact about it has a validity period, and every source keeps its own version of the facts. You ask the database what was true at any instant, according to the best source.

```sql
CREATE EXTENSION combu CASCADE;        -- with btree_gist and postgis
SET combu.as_of = '2019-06-01';
SELECT * FROM registry.hierarchy_tree('admin');   -- the tree as it was then
```

!!! info "Status"
    **0.1.0**, early and moving fast. The registry core is in place: entities, claims, types, hierarchies, aliases, geometry, datasets and priorities. Next come time series, forecasts and scenarios (see the [roadmap](roadmap.md)). Until 1.0, minor versions may change the contracts.

## Ideas

1. **Identity never changes.** Everything references `registry.entity.id`, so types can split and tables can be reorganised without touching a reference.
2. **Every fact has a validity period**, a half-open `tstzrange`. PostgreSQL 18's temporal keys (`WITHOUT OVERLAPS`, `PERIOD`) enforce the rules.
3. **Several sources, one truth at read time.** Each dataset keeps its own versions. Its `priority` decides what views and functions show, and disagreements stay queryable.
4. **The rules live in the database.** Any language that speaks SQL can use combu. Clients are thin.
5. **The core knows no subject.** Domain extensions add entity types, hierarchies and tables (geography, an electrical system, ...).

## Layers

| Layer | What |
|---|---|
| **combu**, the extension | the `registry` and `asof` schemas: tables, constraints, triggers and functions |
| **Domain extensions** | PostgreSQL extensions that require combu and add a subject's structure (planned: `combu_geo`, `combu_power`) |
| **Clients** | thin libraries; [combu-py](https://github.com/Nando-Ferreira-Farias/combu/tree/main/clients/python) is the first |
| **Applications** | projects that use combu, such as an energy-market analysis |

## Where to go next

| I want to… | Read |
|---|---|
| install it | [Install](install.md) |
| understand the tables and the rules | [Data model](model.md) |
| look up a function | [SQL reference](reference.md) |
| back up and restore a database that uses it | [Backups](backups.md) |
| change combu itself | [Development](development.md) |
| know why it works this way | [Decisions](decisions/index.md) |
