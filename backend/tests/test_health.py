"""Smoke tests — require a valid DATABASE_URL (see backend/README.md)."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_ok():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data.get("status") == "ok"
    assert "ai_provider" in data
    assert "webhook_max_per_minute" in data
