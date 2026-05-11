"""Structured HTTP_JSON access logs on business routes (Render grep)."""

from __future__ import annotations

import logging

from fastapi.testclient import TestClient

from app.main import app

# Same shared TestClient pattern as other integration tests: do not use `with TestClient(app)`
# as context manager — exiting it runs app lifespan shutdown and `engine.dispose()`, which
# wipes the in-memory SQLite shared across the suite (see conftest.py DATABASE_URL).
client = TestClient(app)


def test_unauthenticated_business_route_emits_http_json(caplog) -> None:
    caplog.set_level(logging.INFO, logger="app.main")
    r = client.get(
        "/v1/businesses/00000000-0000-0000-0000-000000000001/item-categories",
    )
    assert r.status_code in (401, 403, 422)
    assert any("HTTP_JSON" in rec.message for rec in caplog.records), caplog.text
