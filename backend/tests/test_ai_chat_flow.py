"""In-app assistant chat — preview and grounded queries."""

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def _disable_query_llm_overlay(monkeypatch: pytest.MonkeyPatch):
    """Keep tests deterministic — no live LLM phrasing on grounded query replies."""

    async def _fake(*_a, **_k):
        return None, {"provider_used": None, "failover": [], "failover_used": False}

    monkeypatch.setattr(
        "app.services.app_assistant_chat.synthesize_app_query_reply",
        _fake,
    )


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


def test_ai_chat_query_today():
    h, bid = _register_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={"messages": [{"role": "user", "content": "summary today"}]},
        headers=h,
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data.get("intent") == "query"
    assert "today" in data.get("reply", "").lower()


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


def test_ai_chat_create_supplier_preview_and_confirm():
    h, bid = _register_and_business()
    r1 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={"messages": [{"role": "user", "content": "create supplier Ravi Test"}]},
        headers=h,
    )
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
    assert d1.get("intent") == "entity_preview"
    tok = d1.get("preview_token")
    assert tok
    draft = d1.get("entry_draft")
    assert draft and draft.get("__assistant__") == "entity"

    r2 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [{"role": "user", "content": "yes"}],
            "preview_token": tok,
            "entry_draft": draft,
        },
        headers=h,
    )
    assert r2.status_code == 200, r2.text
    d2 = r2.json()
    assert d2.get("intent") == "entity_saved"
    assert d2.get("saved_entry", {}).get("entity") == "supplier"


def test_ai_chat_create_broker_preview_and_confirm():
    h, bid = _register_and_business()
    r1 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={"messages": [{"role": "user", "content": "create broker Ramesh commission 2%"}]},
        headers=h,
    )
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
    assert d1.get("intent") == "entity_preview"
    tok = d1.get("preview_token")
    assert tok
    r2 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [{"role": "user", "content": "yes"}],
            "preview_token": tok,
            "entry_draft": d1.get("entry_draft"),
        },
        headers=h,
    )
    assert r2.status_code == 200, r2.text
    d2 = r2.json()
    assert d2.get("intent") == "entity_saved"
    assert d2.get("saved_entry", {}).get("entity") == "broker"


def test_ai_chat_create_category_rice_biriyani():
    h, bid = _register_and_business()
    r1 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [{"role": "user", "content": "create category rice > biriyani"}],
        },
        headers=h,
    )
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
    assert d1.get("intent") == "entity_preview"
    tok = d1.get("preview_token")
    r2 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [{"role": "user", "content": "yes"}],
            "preview_token": tok,
            "entry_draft": d1.get("entry_draft"),
        },
        headers=h,
    )
    assert r2.status_code == 200, r2.text
    assert r2.json().get("intent") == "entity_saved"


def test_ai_chat_create_item_under_category():
    h, bid = _register_and_business()
    r0 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={"messages": [{"role": "user", "content": "create category Rice"}]},
        headers=h,
    )
    assert r0.status_code == 200
    d0 = r0.json()
    client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [{"role": "user", "content": "yes"}],
            "preview_token": d0["preview_token"],
            "entry_draft": d0["entry_draft"],
        },
        headers=h,
    )
    r1 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [
                {"role": "user", "content": "create item basmati 50kg bag under Rice"},
            ],
        },
        headers=h,
    )
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
    assert d1.get("intent") == "entity_preview"
    assert "basmati" in d1.get("reply", "").lower()
    r2 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [{"role": "user", "content": "yes"}],
            "preview_token": d1["preview_token"],
            "entry_draft": d1["entry_draft"],
        },
        headers=h,
    )
    assert r2.status_code == 200, r2.text
    assert r2.json().get("saved_entry", {}).get("entity") == "catalog_item"


def test_ai_chat_pending_preview_requires_yes_no():
    """Do not start a new parse while a preview is open (same preview_token)."""
    h, bid = _register_and_business()
    r1 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={"messages": [{"role": "user", "content": "create supplier Pending Gate"}]},
        headers=h,
    )
    assert r1.status_code == 200, r1.text
    d1 = r1.json()
    tok = d1.get("preview_token")
    draft = d1.get("entry_draft")
    assert tok and d1.get("intent") == "entity_preview"

    r2 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [{"role": "user", "content": "100 kg rice from X 700"}],
            "preview_token": tok,
            "entry_draft": draft,
        },
        headers=h,
    )
    assert r2.status_code == 200, r2.text
    d2 = r2.json()
    assert d2.get("intent") == "clarify"
    assert d2.get("preview_token") == tok
    assert "YES" in d2.get("reply", "") or "yes" in d2.get("reply", "").lower()

    r3 = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [{"role": "user", "content": "no"}],
            "preview_token": tok,
            "entry_draft": draft,
        },
        headers=h,
    )
    assert r3.status_code == 200, r3.text
    assert r3.json().get("intent") == "cancelled"


def test_ai_chat_query_reply_source_deterministic():
    h, bid = _register_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={"messages": [{"role": "user", "content": "profit this month"}]},
        headers=h,
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data.get("reply_source") == "deterministic"
    assert data.get("llm_failover_used") is False


def test_extract_intent_failover_gemini_then_groq(monkeypatch: pytest.MonkeyPatch):
    """Ordered failover for structured intent: Gemini returns nothing, Groq returns JSON."""
    calls: list[str] = []

    async def gem_fail(_t, _s, _k):
        calls.append("gemini")
        return None

    async def groq_ok(_t, _s, _k):
        calls.append("groq")
        return {
            "intent": "create_supplier",
            "data": {"supplier_name": "Failover Co"},
            "missing_fields": [],
            "reply_text": "",
        }

    async def oa_fail(_t, _s, _k):
        calls.append("openai")
        return None

    async def fake_keys(_s, _d):
        return {"gemini": "gk", "groq": "qk", "openai": "ok"}

    monkeypatch.setattr("app.services.llm_failover.resolve_provider_keys", fake_keys)
    monkeypatch.setattr("app.services.llm_intent._gemini_json", gem_fail)
    monkeypatch.setattr("app.services.llm_intent._groq_json", groq_ok)
    monkeypatch.setattr("app.services.llm_intent._openai_json", oa_fail)

    # Avoid rule-based `create supplier …` so the LLM path runs.
    h, bid = _register_and_business()
    r = client.post(
        f"/v1/businesses/{bid}/ai/chat",
        json={
            "messages": [
                {
                    "role": "user",
                    "content": "register supplier Failover Co for purchases",
                }
            ]
        },
        headers=h,
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data.get("intent") == "entity_preview"
    assert data.get("llm_provider") == "groq"
    assert data.get("llm_failover_used") is True
    assert calls == ["gemini", "groq"]
