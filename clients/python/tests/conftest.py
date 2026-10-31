"""Integration tests create their own database,
`combu_test`, on the server DATABASE_URL points at (default: the local Compose database)."""

import os
from collections.abc import Iterator

import pytest
from sqlalchemy import Engine, create_engine, make_url, text

DEFAULT_URL = "postgresql+psycopg://postgres:secret@localhost:5432/postgres"
TEST_DATABASE = "combu_test"


@pytest.fixture(scope="session")
def server_url() -> str:
    return os.environ.get("DATABASE_URL", DEFAULT_URL)


@pytest.fixture
def empty_url(server_url: str) -> Iterator[str]:
    """A brand-new empty database for each test, dropped afterwards."""
    admin = create_engine(
        make_url(server_url).set(database="postgres"), isolation_level="AUTOCOMMIT"
    )
    drop = text(f"DROP DATABASE IF EXISTS {TEST_DATABASE} WITH (FORCE)")
    with admin.connect() as conn:
        conn.execute(drop)
        conn.execute(text(f"CREATE DATABASE {TEST_DATABASE}"))
    yield make_url(server_url).set(database=TEST_DATABASE).render_as_string(hide_password=False)
    with admin.connect() as conn:
        conn.execute(drop)
    admin.dispose()


@pytest.fixture
def empty_db(empty_url: str) -> Iterator[Engine]:
    engine = create_engine(empty_url)
    yield engine
    engine.dispose()
