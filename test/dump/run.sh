#!/usr/bin/env bash
# Dump a database that uses combu, restore it into a new one, and check that every registry
# table came back with the same rows and that identity sequences continue where they were.
# Needs psql and pg_dump for a running server (PG* environment variables).
set -euo pipefail
cd "$(dirname "$0")"
psql=(psql -X -q -v ON_ERROR_STOP=1)
src=combu_dump_src
dst=combu_dump_dst

for db in "$src" "$dst"; do
  "${psql[@]}" -d postgres -c "DROP DATABASE IF EXISTS $db" -c "CREATE DATABASE $db TEMPLATE template0"
done
"${psql[@]}" -d "$src" -f fixture.sql
# One transaction: the extension's triggers exist before the data comes back, and the deferred
# hierarchy check must run once every table is loaded (docs/backups.md).
pg_dump -d "$src" | "${psql[@]}" --single-transaction -d "$dst" >/dev/null

before=$("${psql[@]}" -d "$src" -At -f contents.sql)
after=$("${psql[@]}" -d "$dst" -At -f contents.sql)
if [[ "$before" != "$after" ]]; then
  diff <(echo "$before") <(echo "$after") || true
  echo "dump/restore: contents differ" >&2
  exit 1
fi
next=$("${psql[@]}" -d "$dst" -At -c "INSERT INTO registry.dataset (key, kind, priority)
  VALUES ('c', 'source', 100) RETURNING id")
[[ "$next" == 3 ]] || { echo "dump/restore: identity sequence restarted ($next)" >&2; exit 1; }

for db in "$src" "$dst"; do "${psql[@]}" -d postgres -c "DROP DATABASE $db"; done
echo "dump/restore: $(echo "$before" | wc -l) tables identical"
