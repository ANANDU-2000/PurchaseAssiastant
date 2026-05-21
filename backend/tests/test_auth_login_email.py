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
