# combu

A database core for energy-market data and anything else that is **things that change over time, described by several sources**. It's built on PostgreSQL 18. The core holds the logic and doesn't depend on the data it holds; data comes in through well-defined paths. ([ADR 0007](../docs/adr/0007-combu-sql-core.md))

combu is developed inside the `summary` repository until its core is stable, and then moves to a repository of its own.

## Layers

| Layer | What | Where |
|---|---|---|
| **combu-db**, the core | PostgreSQL schemas, constraints, functions and views: entities, claims, types, hierarchies, aliases, geometry, datasets and priorities; later time series. Every rule that defines correct data lives here. | `db/` (plain SQL, see [db/README.md](db/README.md)) |
| **Clients** | Thin libraries that connect, parse files into the data contract, call the core and present results. | `py/`: **combu-py**, the Python client (`pip` name `combu`) |
| **Domain extensions** | Structure for a subject, in the same form as the core: geography, the electrical system, time series. | later `db/<extension>/` |
| **Interface extensions** | Ways in and out: combu-api (HTTP), loader helpers, CLI. | later |
| **Applications** | Projects that use combu and bring their own data, loaders and UI. | e.g. `summary` |

The core has two contracts:

- **The database contract**: its tables, views and functions, usable from any language that speaks SQL.
- **The data contract**: a dataset's desired state (entities, claims, facts with periods) and the rules for applying it. The curated TSV folder format is one serialisation of it.

## Status

| Step (ADR 0007) | State |
|---|---|
| 1. The `combu/` layout and the SQL migration runner; the core's tables and functions as combu-db's first migrations | done |
| 2. The catalog as data only (no copy in client code) | next |
| 3. Sync over staging tables, as a SQL function | |
| 4. View generation in SQL | |
| 5. Geography and electrical as domain extensions | |

Until those steps are done, the rest of the client code (sync, TSV files, queries, generated views) still lives in `summary.registry` and moves into combu-py as its logic moves into SQL.

## What the core must eventually answer

The first application analyses Latin American electricity markets (Chile, Colombia, Peru, Argentina first, other regions later). Its questions show where the core has to go. These are design drivers, not commitments:

| Question | What it needs from the core |
|---|---|
| "How has Chile's renewable capacity grown in the past years?" | What exists at each date, with its attributes and hierarchies, from several sources ranked by priority. **In place.** |
| "What are the main price drivers in Colombia and Peru?" | Time series of prices, demand, hydrology, fuel prices and generation by technology. They must line up in time across markets with different time zones, units and currencies, and aggregate along hierarchies at each instant. |
| "What price should Argentina expect next year if El Niño comes?" | Forecasts and scenarios as first-class data. That means the time a forecast was issued (its vintage) as well as the time it is about, scenario dimensions, and entities that belong to no country (a climate index such as ENSO). |
| Any of these, asked of an agent | A described catalog: what each entity type, hierarchy, metric and dataset means, in the database, so a client or an agent can discover what can be asked. |

When a study needs the core to change, the core changes. A new migration may redesign whatever the study shows to be wrong.
