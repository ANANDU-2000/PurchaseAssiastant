"""Entry create: preview_token required for confirm=true (integration via TestClient)."""

import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

_LINE = {
    "item_name": "Rice",
    "qty": 10,
    "unit": "kg",
    "buy_price": 40,
    "landing_cost": 42,
}


def _register_and_business():
    u = uuid.uuid4().hex[:10]
    email = f"e{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}
    br = client.get("/v1/me/businesses", headers=h)
    assert br.status_code == 200, br.text
    bid = br.json()[0]["id"]
    return h, bid


def test_preview_returns_token_and_confirm_saves():
    h, bid = _register_and_business()
    body = {
        "entry_date": "2026-04-10",
        "confirm": False,
        "lines": [_LINE],
    }
    pr = client.post(f"/v1/businesses/{bid}/entries", json=body, headers=h)
    assert pr.status_code == 200, pr.text
    data = pr.json()
    assert data.get("preview") is True
    assert data.get("preview_token")
    pt = data["preview_token"]

    body["confirm"] = True
    body["preview_token"] = pt
    cr = client.post(f"/v1/businesses/{bid}/entries", json=body, headers=h)
    assert cr.status_code == 201, cr.text
    assert cr.json().get("id")


def test_confirm_without_preview_token_400():
    h, bid = _register_and_business()
    body = {
        "entry_date": "2026-04-11",
        "confirm": True,
        "lines": [_LINE],
    }
    cr = client.post(f"/v1/businesses/{bid}/entries", json=body, headers=h)
    assert cr.status_code == 400
    assert "preview" in cr.json().get("detail", "").lower()


def test_preview_token_service_unit():
    from app.schemas.entries import EntryCreateRequest, EntryLineInput
    from app.services.entry_preview_token import consume_preview_token, issue_preview_token, verify_preview_token

    uid = uuid.uuid4()
    bid = uuid.uuid4()
    line = EntryLineInput(
        item_name="X",
        qty=1,
        unit="kg",
        buy_price=1,
        landing_cost=1,
    )
    body = EntryCreateRequest(
        entry_date=__import__("datetime").date.today(),
        confirm=False,
        lines=[line],
    )
    tok = issue_preview_token(body, user_id=uid, business_id=bid)
    body_confirm = EntryCreateRequest(
        entry_date=body.entry_date,
        confirm=True,
        preview_token=tok,
        lines=[line],
    )
    ok, err = verify_preview_token(tok, body_confirm, user_id=uid, business_id=bid)
    assert ok and err == ""
    consume_preview_token(tok)
    ok2, err2 = verify_preview_token(tok, body_confirm, user_id=uid, business_id=bid)
    assert not ok2 and err2


def test_confirm_duplicate_409_then_force_succeeds():
    h, bid = _register_and_business()
    line = {
        "item_name": "Wheat",
        "qty": 5,
        "unit": "kg",
        "buy_price": 20,
        "landing_cost": 22,
    }
    day = "2026-04-12"

    def preview_and_confirm(force_dup: bool):
        pr = client.post(
            f"/v1/businesses/{bid}/entries",
            json={"entry_date": day, "confirm": False, "lines": [line]},
            headers=h,
        )
        assert pr.status_code == 200, pr.text
        pt = pr.json()["preview_token"]
        body = {
            "entry_date": day,
            "confirm": True,
            "preview_token": pt,
            "lines": [line],
        }
        if force_dup:
            body["force_duplicate"] = True
        return client.post(f"/v1/businesses/{bid}/entries", json=body, headers=h)

    first = preview_and_confirm(force_dup=False)
    assert first.status_code == 201, first.text

    second = preview_and_confirm(force_dup=False)
    assert second.status_code == 409, second.text

    third = preview_and_confirm(force_dup=True)
    assert third.status_code == 201, third.text


def test_preview_splits_transport_across_lines():
    h, bid = _register_and_business()
    pr = client.post(
        f"/v1/businesses/{bid}/entries",
        json={
            "entry_date": "2026-04-13",
            "confirm": False,
            "transport_cost": 100,
            "lines": [
                {
                    "item_name": "A",
                    "qty": 10,
                    "unit": "kg",
                    "buy_price": 40,
                    "landing_cost": 0,
                },
                {
                    "item_name": "B",
                    "qty": 10,
                    "unit": "kg",
                    "buy_price": 40,
                    "landing_cost": 0,
                },
            ],
        },
        headers=h,
    )
    assert pr.status_code == 200, pr.text
    lines = pr.json()["lines"]
    assert len(lines) == 2
    assert abs(lines[0]["landing_cost"] - 45) < 0.01
    assert abs(lines[1]["landing_cost"] - 45) < 0.01
