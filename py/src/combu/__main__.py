"""`combu migrate` and `combu status`: install or inspect combu-db without any application.

The database URL comes from `--url` or the DATABASE_URL environment variable.
"""

import argparse
import os
import sys

from sqlalchemy import create_engine

from combu import migrate


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="combu", description="combu-db migrations.")
    parser.add_argument("command", choices=["migrate", "status"])
    parser.add_argument("--url", default=os.environ.get("DATABASE_URL"), help="SQLAlchemy URL")
    parser.add_argument(
        "--component", action="append", help="Component to include (repeatable; default core)."
    )
    args = parser.parse_args(argv)
    if not args.url:
        parser.error("pass --url or set DATABASE_URL")
    components = args.component or ["core"]
    engine = create_engine(args.url)
    try:
        with engine.begin() as conn:
            if args.command == "migrate":
                done = migrate.migrate(conn, components)
                for migration in done:
                    print(f"applied {migration}")
                print("up to date" if not done else f"{len(done)} applied")
            else:
                todo = migrate.pending(conn, components)
                for (component, version), (name, _) in sorted(migrate.applied(conn).items()):
                    print(f"applied  {component} {version:04d}_{name}")
                for migration in todo:
                    print(f"pending  {migration}")
    except migrate.MigrationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    finally:
        engine.dispose()
    return 0


if __name__ == "__main__":
    sys.exit(main())
