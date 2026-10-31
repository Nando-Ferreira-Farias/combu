"""The combu-db migration runner (combu/db/README.md)."""

import shutil
from pathlib import Path

import pytest
from sqlalchemy import Engine, text

from combu import migrate
from combu.__main__ import main
from combu.migrate import MigrationError


def component(tmp_path: Path, *names: str) -> Path:
    for name in names:
        path = tmp_path / "core" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"-- {name}\n", encoding="utf-8")
    return tmp_path


def test_the_core_is_numbered_without_gaps() -> None:
    names = [str(m) for m in migrate.discover("core")]
    assert names[:2] == ["core 0001_registry_tables", "core 0002_registry_functions"]


def test_files_are_ordered_by_number(tmp_path: Path) -> None:
    root = component(tmp_path, "0002_b.sql", "0001_a.sql")
    assert [m.version for m in migrate.discover("core", root)] == [1, 2]


def test_gaps_and_bad_names_are_refused(tmp_path: Path) -> None:
    with pytest.raises(MigrationError, match="expected migration 0002"):
        migrate.discover("core", component(tmp_path, "0001_a.sql", "0003_c.sql"))
    with pytest.raises(MigrationError, match="expected a name like"):
        migrate.discover("core", component(tmp_path / "x", "1_a.sql"))
    with pytest.raises(MigrationError, match="no combu-db component 'power'"):
        migrate.discover("power", tmp_path)


@pytest.mark.integration
def test_migrate_installs_the_core_once(empty_db: Engine) -> None:
    with empty_db.begin() as conn:
        done = migrate.migrate(conn)
    with empty_db.begin() as conn:
        again = migrate.migrate(conn)
        recorded = conn.execute(
            text("SELECT component, version, name FROM combu.migration ORDER BY version")
        ).all()
        functions = conn.execute(text("SELECT to_regproc('registry.hierarchy_tree')")).scalar()

    assert [str(m) for m in done] == [str(m) for m in migrate.discover("core")]
    assert again == []
    assert recorded[0] == ("core", 1, "registry_tables")
    assert functions is not None


@pytest.mark.integration
def test_an_edited_migration_is_refused(empty_db: Engine, tmp_path: Path) -> None:
    root = tmp_path / "db"
    shutil.copytree(migrate.DB_ROOT, root)
    with empty_db.begin() as conn:
        migrate.migrate(conn, root=root)
    first = next((root / "core").glob("0001_*.sql"))
    first.write_text(first.read_text() + "\n-- edited\n")

    edited = "0001_registry_tables changed after it was applied"
    with pytest.raises(MigrationError, match=edited), empty_db.begin() as conn:
        migrate.migrate(conn, root=root)


@pytest.mark.integration
def test_a_database_newer_than_the_files_is_refused(empty_db: Engine) -> None:
    with empty_db.begin() as conn:
        migrate.migrate(conn)
        conn.execute(text("INSERT INTO combu.migration VALUES ('core', 999, 'future', 'x', now())"))
    newer = r"migrations \[999\] that are not on disk"
    with pytest.raises(MigrationError, match=newer), empty_db.begin() as conn:
        migrate.pending(conn)


@pytest.mark.integration
def test_a_failed_migration_leaves_nothing_behind(empty_db: Engine, tmp_path: Path) -> None:
    root = component(tmp_path, "0001_a.sql")
    (root / "core" / "0001_a.sql").write_text("CREATE TABLE t (x int); SELECT 1/0;")

    with pytest.raises(Exception, match="division by zero"), empty_db.begin() as conn:
        migrate.migrate(conn, root=root)

    with empty_db.connect() as conn:
        assert conn.execute(text("SELECT to_regclass('combu.migration')")).scalar() is None
        assert conn.execute(text("SELECT to_regclass('t')")).scalar() is None


@pytest.mark.integration
def test_the_command_line(empty_url: str, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["status", "--url", empty_url]) == 0
    assert "pending  core 0001_registry_tables" in capsys.readouterr().out
    assert main(["migrate", "--url", empty_url]) == 0
    assert main(["migrate", "--url", empty_url]) == 0
    assert capsys.readouterr().out.splitlines()[-1] == "up to date"
