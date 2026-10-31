"""`combu install` and `combu status`: the combu extension in a database, from the shell.

The database URL comes from `--url` or the DATABASE_URL environment variable.
"""

import argparse
import os
import sys

from sqlalchemy import create_engine

from combu import extension


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="combu", description="The combu extension.")
    parser.add_argument("command", choices=["install", "status"])
    parser.add_argument("--url", default=os.environ.get("DATABASE_URL"), help="SQLAlchemy URL")
    parser.add_argument("--version", help="Version to install or update to [default: latest].")
    args = parser.parse_args(argv)
    if not args.url:
        parser.error("pass --url or set DATABASE_URL")
    engine = create_engine(args.url)
    try:
        with engine.begin() as conn:
            if args.command == "install":
                before = extension.status(conn).installed
                after = extension.install(conn, args.version)
                change = "" if before == after else f" (was {before or 'absent'})"
                print(f"combu {after}{change}")
            else:
                current = extension.status(conn)
                print(f"installed  {current.installed or '-'}")
                print(f"default    {current.default or '- (not on this server)'}")
                print(f"available  {', '.join(current.available) or '-'}")
    except extension.ExtensionError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    finally:
        engine.dispose()
    return 0


if __name__ == "__main__":
    sys.exit(main())
