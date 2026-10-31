"""Installing and updating the extension. Integration tests need a server that has the combu
files (the combu Docker image); they are skipped elsewhere."""

import pytest
from sqlalchemy import Engine, text

from combu import extension
from combu.__main__ import main
from combu.extension import ExtensionError


def test_versions_sort_numerically() -> None:
    assert extension._version_key("0.10.0") > extension._version_key("0.9.1")


@pytest.fixture
def server_has_combu(empty_db: Engine) -> Engine:
    with empty_db.connect() as conn:
        if extension.status(conn).default is None:
            pytest.skip("the combu extension is not installed on this server")
    return empty_db


@pytest.mark.integration
def test_install_creates_the_extension_once(server_has_combu: Engine) -> None:
    with server_has_combu.begin() as conn:
        version = extension.install(conn)
    with server_has_combu.begin() as conn:
        again = extension.install(conn)
        current = extension.status(conn)
        tables = conn.execute(
            text("SELECT count(*) FROM pg_tables WHERE schemaname = 'registry'")
        ).scalar_one()

    assert version == again == current.installed == current.default
    assert tables > 0


@pytest.mark.integration
def test_unknown_versions_are_refused(server_has_combu: Engine) -> None:
    unknown = r"99\.0\.0 is not available"
    with pytest.raises(ExtensionError, match=unknown), server_has_combu.begin() as conn:
        extension.install(conn, "99.0.0")
    invalid = "not a combu version"
    with pytest.raises(ExtensionError, match=invalid), server_has_combu.begin() as conn:
        extension.install(conn, "latest; DROP TABLE x")


@pytest.mark.integration
def test_the_command_line(
    server_has_combu: Engine, empty_url: str, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["status", "--url", empty_url]) == 0
    assert "installed  -" in capsys.readouterr().out
    assert main(["install", "--url", empty_url]) == 0
    assert "(was absent)" in capsys.readouterr().out
