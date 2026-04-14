"""In-app assistant chat — preview and grounded queries."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_and_business():
    import uuid

    u = uuid.uuid4().hex[:10]
    email = f"chat{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"cu{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}
    br = client.get("/v1/me/businesses", headers=h)
    assert br.status_code == 200, br.text
    bid = br.json()[0]["id"]
    return h, bid


def test_ai_chat_help_intent():
    h, bid = _register_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={"messages": [{"role": "user", "content": "help"}]},
        headers=h,
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data.get("intent") == "help"
    assert "Assistant" in data.get("reply", "") or "purchase" in data.get("reply", "").lower()


def test_ai_chat_query_grounded():
    h, bid = _register_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={"messages": [{"role": "user", "content": "profit this month"}]},
        headers=h,
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data.get("intent") == "query"
    assert "profit" in data.get("reply", "").lower()


def test_ai_chat_stub_purchase_preview():
    h, bid = _register_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [
                {
                    "role": "user",
                    "content": "100 kg rice ₹700 ₹720",
                }
            ]
        },
        headers=h,
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data.get("intent") == "add_purchase_preview"
    assert data.get("preview_token")
    assert data.get("entry_draft")
