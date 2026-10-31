# combu-py

The Python client of [combu](../../README.md). For now it installs, updates and inspects the
extension:

```bash
combu status  --url postgresql+psycopg://user:pass@host/db
combu install --url …            # CREATE EXTENSION combu CASCADE, or ALTER EXTENSION … UPDATE
```

```python
from combu import extension

with engine.begin() as conn:
    extension.install(conn)  # the server's default version
```

Tests: `uv run pytest` (unit), and with a server that has combu (`docker/Dockerfile`):
`DATABASE_URL=postgresql+psycopg://postgres:secret@localhost:55432/postgres uv run pytest -m integration`.
