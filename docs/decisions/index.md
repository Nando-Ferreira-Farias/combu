# Decisions

Short records of the choices that shape combu, so later changes can see what was traded off. Each one follows Michael Nygard's format (**Context**, **Decision**, **Consequences**) and has a status: `Accepted`, `Superseded by NNNN` or `Deprecated`.

combu started inside an application, summary, which analyses electricity markets. The first four decisions were made there and are kept here with their original wording. They still mention that project's names and examples (Chilean power plants, its curated folders), but what they decide is combu's.

| Decision | | Status |
|---|---|---|
| [0001](0001-temporal-entity-registry.md) | Temporal entity registry on PostgreSQL 18 | Accepted |
| [0002](0002-several-sources-per-fact.md) | Several sources per fact, resolved by dataset priority | Accepted |
| [0003](0003-sql-core.md) | A database core in SQL with thin clients and extensions | Accepted; its migration mechanism superseded by 0004 |
| [0004](0004-postgres-extension.md) | combu ships as a PostgreSQL extension, in its own repository | Accepted |

To add one, copy the latest file, give it the next number, keep it to about a page, and link it here and in `zensical.toml`.
