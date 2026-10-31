"""Apply combu-db's SQL migrations (combu/db/README.md).

combu-db is plain SQL. Each component (the core, and later each extension) is a directory of
numbered files, applied in order and recorded in `combu.migration` with their checksum. This
module is one runner for that contract; a runner in any other language does the same.

Migrations are forward-only: a change to the schema is a new file, never an edit of an applied
one, and the runner refuses to continue if an applied file changed on disk.
"""

import hashlib
import re
from collections.abc import Sequence
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

from sqlalchemy import Connection, text

# combu/db in a source checkout (combu/py/src/combu/migrate.py -> combu/db).
DB_ROOT = Path(__file__).resolve().parents[3] / "db"
FILE_NAME = re.compile(r"^(?P<version>\d{4})_(?P<name>[a-z0-9_]+)\.sql$")

BOOTSTRAP = """
CREATE SCHEMA IF NOT EXISTS combu;
CREATE TABLE IF NOT EXISTS combu.migration (
  component  text NOT NULL,
  version    integer NOT NULL,
  name       text NOT NULL,
  checksum   text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (component, version)
);
COMMENT ON TABLE combu.migration IS 'combu-db migrations applied to this database.';
"""


class MigrationError(Exception):
    """The files on disk and the database disagree; reported as is."""


@dataclass(frozen=True)
class Migration:
    component: str
    version: int
    name: str
    path: Path

    @cached_property
    def sql(self) -> str:
        return self.path.read_text(encoding="utf-8")

    @cached_property
    def checksum(self) -> str:
        return hashlib.sha256(self.sql.encode("utf-8")).hexdigest()

    def __str__(self) -> str:
        return f"{self.component} {self.version:04d}_{self.name}"


def discover(component: str, root: Path = DB_ROOT) -> list[Migration]:
    """A component's migrations in order; numbers must run 1, 2, 3 ... without gaps."""
    directory = root / component
    if not directory.is_dir():
        raise MigrationError(f"no combu-db component {component!r} in {root}")
    migrations = []
    for path in sorted(directory.glob("*.sql")):
        match = FILE_NAME.match(path.name)
        if match is None:
            raise MigrationError(f"{path}: expected a name like 0001_short_name.sql")
        migrations.append(
            Migration(component, int(match["version"]), match["name"], path.resolve())
        )
    for expected, migration in enumerate(migrations, start=1):
        if migration.version != expected:
            raise MigrationError(f"{component}: expected migration {expected:04d}, not {migration}")
    return migrations


def applied(conn: Connection) -> dict[tuple[str, int], tuple[str, str]]:
    """(component, version) -> (name, checksum) of every recorded migration."""
    if conn.execute(text("SELECT to_regclass('combu.migration')")).scalar() is None:
        return {}
    rows = conn.execute(text("SELECT component, version, name, checksum FROM combu.migration"))
    return {(row.component, row.version): (row.name, row.checksum) for row in rows}


def pending(
    conn: Connection, components: Sequence[str] = ("core",), root: Path = DB_ROOT
) -> list[Migration]:
    """Migrations not applied yet, after checking the applied ones against the files."""
    done = applied(conn)
    todo = []
    for component in components:
        on_disk = discover(component, root)
        versions = {m.version for m in on_disk}
        unknown = sorted(v for (c, v) in done if c == component and v not in versions)
        if unknown:
            raise MigrationError(
                f"{component}: the database has migrations {unknown} that are not on disk; "
                "this checkout is older than the database"
            )
        for migration in on_disk:
            record = done.get((component, migration.version))
            if record is None:
                todo.append(migration)
            elif record[1] != migration.checksum:
                raise MigrationError(
                    f"{migration} changed after it was applied; never edit an applied "
                    "migration, add a new one"
                )
    return todo


def migrate(
    conn: Connection, components: Sequence[str] = ("core",), root: Path = DB_ROOT
) -> list[Migration]:
    """Apply pending migrations in the caller's transaction; return what was applied.

    An advisory lock makes concurrent runs wait for each other. The caller commits.
    """
    conn.execute(text("SELECT pg_advisory_xact_lock(hashtext('combu.migrate'))"))
    _run(conn, BOOTSTRAP)
    todo = pending(conn, components, root)
    for migration in todo:
        _run(conn, migration.sql)
        conn.execute(
            text(
                "INSERT INTO combu.migration (component, version, name, checksum) "
                "VALUES (:component, :version, :name, :checksum)"
            ),
            {
                "component": migration.component,
                "version": migration.version,
                "name": migration.name,
                "checksum": migration.checksum,
            },
        )
    return todo


def _run(conn: Connection, sql: str) -> None:
    """Run a whole SQL file as is, through the driver: no parameter or `%` handling."""
    cursor = conn.connection.cursor()
    try:
        cursor.execute(sql)
    finally:
        cursor.close()
