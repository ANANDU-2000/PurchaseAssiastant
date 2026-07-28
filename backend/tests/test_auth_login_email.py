import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _owner_with_staff():
    u = uuid.uuid4().hex[:8]
    suffix = u[-8:]
    phone_digits = "".join(c for c in suffix if c.isdigit())
    if len(phone_digits) < 8:
        phone_digits = f"{int(u[:8], 16) % 100000000:08d}"
    phone = f"98{phone_digits[:8]}"
    staff_email = f"staff{suffix}@test.hexa.local"
    owner_email = f"owner{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ow{u}", "email": owner_email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=h,
        json={
            "full_name": "Krishna Staff",
            "phone": phone,
            "email": staff_email,
            "role": "staff",
        },
    )
    assert cr.status_code == 201, cr.text
    pwd = cr.json()["generated_password"]
    return pwd, staff_email, owner_email, bid, h


def test_login_by_email():
    pwd, staff_email, _owner, _bid, _h = _owner_with_staff()
    r = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": pwd},
    )
    assert r.status_code == 200, r.text
    assert r.json().get("access_token")


def test_login_legacy_identifier_field():
    """Older Flutter web builds POST `identifier` instead of `email`."""
    pwd, staff_email, _owner, _bid, _h = _owner_with_staff()
    r = client.post(
        "/v1/auth/login",
        json={"identifier": staff_email, "password": pwd},
    )
    assert r.status_code == 200, r.text


def test_login_wrong_password():
    pwd, staff_email, _owner, _bid, _h = _owner_with_staff()
    r = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": "wrongpass99"},
    )
    assert r.status_code == 401
    assert "password" in r.json()["detail"].lower()


def test_deactivate_user_still_listed_with_include_inactive():
    pwd, staff_email, _owner, bid, h = _owner_with_staff()
    users = client.get(f"/v1/businesses/{bid}/users", headers=h, params={"include_inactive": True})
    staff = next(u for u in users.json() if u["email"] == staff_email)
    client.patch(
        f"/v1/businesses/{bid}/users/{staff['id']}",
        headers=h,
        json={"is_active": False},
    )
    users2 = client.get(f"/v1/businesses/{bid}/users", headers=h, params={"include_inactive": True})
    ids = [u["id"] for u in users2.json()]
    assert staff["id"] in ids
    prof = client.get(f"/v1/businesses/{bid}/users/{staff['id']}", headers=h)
    assert prof.status_code == 200, prof.text


def test_login_blocked_user():
    pwd, staff_email, _owner, bid, h = _owner_with_staff()
    users = client.get(f"/v1/businesses/{bid}/users", headers=h, params={"include_inactive": True})
    staff = next(u for u in users.json() if u["email"] == staff_email)
    client.patch(
        f"/v1/businesses/{bid}/users/{staff['id']}",
        headers=h,
        json={"is_blocked": True},
    )
    r = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": pwd},
    )
    assert r.status_code == 403
    assert "blocked" in r.json()["detail"].lower()


def test_refresh_blocked_user_forbidden():
    """AUTH-C1: blocked users must not mint new tokens via refresh."""
    pwd, staff_email, _owner, bid, h = _owner_with_staff()
    login = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": pwd},
    )
    assert login.status_code == 200, login.text
    refresh = login.json()["refresh_token"]

    users = client.get(f"/v1/businesses/{bid}/users", headers=h, params={"include_inactive": True})
    staff = next(u for u in users.json() if u["email"] == staff_email)
    client.patch(
        f"/v1/businesses/{bid}/users/{staff['id']}",
        headers=h,
        json={"is_blocked": True},
    )

    r = client.post("/v1/auth/refresh", json={"refresh_token": refresh})
    # Block bumps token_version (401) and/or is_blocked gate (403).
    assert r.status_code in (401, 403), r.text
    detail = r.json()["detail"].lower()
    assert "revoked" in detail or "blocked" in detail


def test_refresh_inactive_user_forbidden():
    pwd, staff_email, _owner, bid, h = _owner_with_staff()
    login = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": pwd},
    )
    assert login.status_code == 200, login.text
    refresh = login.json()["refresh_token"]

    users = client.get(f"/v1/businesses/{bid}/users", headers=h, params={"include_inactive": True})
    staff = next(u for u in users.json() if u["email"] == staff_email)
    client.patch(
        f"/v1/businesses/{bid}/users/{staff['id']}",
        headers=h,
        json={"is_active": False},
    )

    r = client.post("/v1/auth/refresh", json={"refresh_token": refresh})
    # Deactivate bumps token_version (401) and/or is_active gate (403).
    assert r.status_code in (401, 403), r.text
    detail = r.json()["detail"].lower()
    assert "revoked" in detail or "inactive" in detail


def test_refresh_active_user_ok():
    pwd, staff_email, _owner, _bid, _h = _owner_with_staff()
    login = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": pwd},
    )
    assert login.status_code == 200, login.text
    r = client.post(
        "/v1/auth/refresh",
        json={"refresh_token": login.json()["refresh_token"]},
    )
    assert r.status_code == 200, r.text
    assert r.json().get("access_token")
    assert r.json().get("refresh_token")


def test_login_persists_user_session():
    """AUTH-H1: login must commit last_active_at / session side effects."""
    pwd, staff_email, _owner, bid, h = _owner_with_staff()
    login = client.post(
        "/v1/auth/login",
        json={"email": staff_email, "password": pwd},
    )
    assert login.status_code == 200, login.text
    sessions = client.get(
        f"/v1/businesses/{bid}/users/active-sessions",
        headers=h,
    )
    assert sessions.status_code == 200, sessions.text
    rows = sessions.json()
    assert isinstance(rows, list)
    emails = {(r.get("email") or "").lower() for r in rows}
    assert staff_email.lower() in emails


def test_login_rate_limited_per_ip():
    """AUTH-M2: brute-force login attempts are throttled per IP."""
    headers = {"X-Forwarded-For": "203.0.113.77"}
    for _ in range(20):
        r = client.post(
            "/v1/auth/login",
            headers=headers,
            json={"email": "nobody@test.hexa.local", "password": "wrongpass99"},
        )
        assert r.status_code in (401, 429), r.text
    blocked = client.post(
        "/v1/auth/login",
        headers=headers,
        json={"email": "nobody@test.hexa.local", "password": "wrongpass99"},
    )
    assert blocked.status_code == 429
    assert "too many" in blocked.json()["detail"].lower()
