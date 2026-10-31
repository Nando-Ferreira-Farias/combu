# Backups

combu's tables belong to the extension. By default, `pg_dump` dumps only an extension's `CREATE EXTENSION` statement, not the data in its tables. combu therefore registers **every table that holds data, and every identity sequence**, with `pg_extension_config_dump`, so dumps include their rows.

## Dump

Nothing special:

```bash
pg_dump -d mydb -Fc -f mydb.dump
```

`pg_dump` may warn about circular foreign keys on `registry.entity_type`. That's its self-reference (`parent_id`); full dumps restore it correctly.

## Restore in one transaction

!!! warning "Always restore in a single transaction"
    ```bash
    pg_restore --single-transaction -d newdb mydb.dump
    psql --single-transaction -d newdb -f mydb.sql        # plain-format dumps
    ```

A restore recreates the extension, and with it combu's triggers, **before** it loads the data. One of those triggers checks hierarchy edges against the hierarchy rules, and it runs when the transaction commits. If each table loads in its own transaction, an edge can be checked before the rules it needs have been loaded, and the restore fails with an error such as `hierarchy … does not allow a … under …`. In one transaction, the check runs once everything is back.

## What is guaranteed

The test suite checks both halves of this:

- **Registration:** every table and sequence in the `registry` schema is registered for dumping (`test/sql/config_dump.sql`).
- **Round trip:** a database with data dumps and restores with identical rows in every registry table, including an application's own table in the `registry` schema, and its identity sequences continue where they were (`test/dump/run.sh`, `make dumpcheck`).

A new table in the extension must be registered in the same release that adds it, and `config_dump` fails until it is.
