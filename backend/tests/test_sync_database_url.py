"""Sync (non-async) database URLs must name psycopg2 explicitly.

SQLAlchemy 2.1 changed the default driver of a bare ``postgresql://`` URL to psycopg v3, which is not in
requirements.txt (psycopg2-binary is). A bare URL made POST /v1/me/bootstrap-workspace fail with a 500
(ModuleNotFoundError: psycopg) on PostgreSQL.
"""

import pytest
from sqlalchemy.engine import make_url

from app.config import get_settings
from app.services.default_workspace import sync_database_url_for_seed


class _PgEngine:
    url = "postgresql+asyncpg://u:p@db.example:5432/hexa"


@pytest.mark.parametrize(
    "raw",
    [
        "postgresql+asyncpg://u:p@db.example:5432/hexa",
        "postgres+asyncpg://u:p@db.example:5432/hexa",
        "postgres://u:p@db.example:5432/hexa",
        "postgresql://u:p@db.example:5432/hexa",
    ],
)
def test_seed_sync_url_uses_psycopg2(monkeypatch, raw):
    monkeypatch.setattr("app.database.engine", _PgEngine())
    monkeypatch.setenv("DATABASE_URL", raw)
    url = sync_database_url_for_seed(get_settings())
    assert url.startswith("postgresql+psycopg2://u:p@db.example:5432/hexa")
    assert make_url(url).get_dialect().driver == "psycopg2"
