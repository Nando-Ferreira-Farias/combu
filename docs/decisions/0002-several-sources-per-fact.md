# 0002: Several sources per fact, resolved by dataset priority

- **Status:** Accepted
- **Date:** 2026-10-31
- **Origin:** ADR 0006 of the summary project, where combu started.

## Context

The registry will be fed by several sources that describe the same things. For example, the Global Energy Monitor trackers and CEN's Infotécnica both list Chile's power plants, and they disagree:

- about values, such as a plant's capacity
- about dates: GEM gives only years, while CEN gives exact days
- about structure, such as which commune or bus a plant belongs to

[decision 0001](0001-temporal-entity-registry.md) gave each fact one version at a time: the key was `(entity, valid WITHOUT OVERLAPS)`. That left two options:

- **Source of record per table.** Only the winning source writes. The losing values live only in the raw archive, and each loader has to know about the others.
- **Every source keeps its own versions**, and readers choose between them.

## Decision

Every source keeps its own versions, and readers see the highest-priority one.

- **One entity per real thing, whatever the number of sources.** Sources identify the same thing through aliases and keys, and a time series always references `entity.id`.
- **Claims.** A dataset that declares an entity **claims** it in `registry.entity_claim`, with its own name and lifetime. Several datasets can claim the same key.
  - The entity's lifetime is the union of all claims: it exists while any source says it does. Claims must touch or overlap, leaving no gap.
  - The entity's name comes from the highest-priority claim.
  - Sources must agree on the entity's type.
  - An entity that nobody claims any more is deleted.
- **Facts are per dataset.** Attribute tables, hierarchy edges, geometry and relations have `dataset_id` in their temporal primary key (`summary.models.core.fact_key`). Each dataset therefore has at most one version at a time, but datasets don't constrain each other.
- **Datasets have a `priority`.** The lowest number wins, and ties go to the dataset key. The defaults are curated 0, derived 50 and source 100. A curated folder sets its priority in `_dataset.tsv`, and a loader sets it in its desired state.
- **Readers resolve by priority, per fact and per instant.**
  - `asof.<type>` views take, for each attribute table, the highest-priority version in force, and name its dataset in a `<table>_dataset` column.
  - `registry.hierarchy_edges(h, ts)` takes each child's highest-priority edge. `hierarchy_tree`, `entity_ancestors` and the other hierarchy functions are built on it.
  - A lower-priority source fills the periods a higher one doesn't cover.
- **Aliases stay single.** They identify entities, so a `(scheme, code)` still means one entity at a time, whichever dataset says so.
- **Conflicts are a report.** `summary registry conflicts` lists overlapping versions from different datasets that differ (attributes, parents and claimed lifetimes), with the winner first.
- **Corrections are a curated dataset that outranks the source.** This replaces the override files that loaders were going to apply.

## Consequences

- Loaders stay independent. Adding a source never changes another source's rows or loader. A new source that disagrees is visible in `conflicts` instead of failing or overwriting.
- Comparing sources is a query, not a re-parse of the raw archive.
- Queries that read the tables directly must resolve sources themselves. Use the `asof` views and the hierarchy functions, or join `registry.dataset` and order by `priority, key`.
- Relations are stored per dataset but not resolved yet: `show` lists every source's rows. Resolving them depends on the relation (each asset's owners as a set from one source, for example), so the theme that adds a relation decides how.
- The edge check refuses a cycle formed by any combination of sources, even one that priorities would never show. That's conservative, but cheap to check.
- A lifetime can only grow when a source is added. A low-quality source that says a plant existed earlier makes it exist earlier. Its versions show in the views only where no better source has one.
