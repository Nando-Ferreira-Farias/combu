"""Install, update and inspect the combu extension in a database.

The extension's files must be on the database server (docs/install.md). PostgreSQL then tracks
the installed version itself; this module only asks it to install or update, and reports.
"""

import re
from dataclasses import dataclass

from sqlalchemy import Connection, text

EXTENSION = "combu"
VERSION = re.compile(r"^\d+\.\d+\.\d+$")


class ExtensionError(Exception):
    """The server can't provide the requested combu; reported as is."""


@dataclass(frozen=True, slots=True)
class Status:
    installed: str | None  # in this database
    default: str | None  # what CREATE EXTENSION installs on this server
    available: tuple[str, ...]  # every version the server has scripts for


def status(conn: Connection) -> Status:
    installed = conn.execute(
        text("SELECT extversion FROM pg_extension WHERE extname = :name"), {"name": EXTENSION}
    ).scalar()
    default = conn.execute(
        text("SELECT default_version FROM pg_available_extensions WHERE name = :name"),
        {"name": EXTENSION},
    ).scalar()
    available = conn.execute(
        text("SELECT version FROM pg_available_extension_versions WHERE name = :name"),
        {"name": EXTENSION},
    ).scalars()
    return Status(installed, default, tuple(sorted(available, key=_version_key)))


def install(conn: Connection, version: str | None = None) -> str:
    """Install combu (and its requirements), or update it, to `version` or the server's
    default. Runs in the caller's transaction; returns the version now installed."""
    current = status(conn)
    if current.default is None:
        raise ExtensionError(
            "the combu extension is not available on this database server; install its files "
            "first (make install, or the combu Docker image)"
        )
    target = version or current.default
    if not VERSION.match(target):
        raise ExtensionError(f"{target!r} is not a combu version (expected like 0.1.0)")
    if target not in current.available:
        available = ", ".join(current.available)
        raise ExtensionError(f"combu {target} is not available on this server (it has {available})")
    if current.installed is None:
        # The version is checked against VERSION above; DDL can't take bound parameters.
        conn.execute(text(f"CREATE EXTENSION {EXTENSION} VERSION '{target}' CASCADE"))
    elif current.installed != target:
        if _version_key(target) < _version_key(current.installed):
            raise ExtensionError(
                f"combu {current.installed} is installed; it can't go back to {target}"
            )
        conn.execute(text(f"ALTER EXTENSION {EXTENSION} UPDATE TO '{target}'"))
    return target


def _version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))
