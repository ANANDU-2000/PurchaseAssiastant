import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_create_staff_user():
    u = uuid.uuid4().hex[:8]
    email = f"owner{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ow{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]

    phone = f"91{uuid.uuid4().int % 100000000:08d}"
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=h,
        json={
            "full_name": "Ravi Staff",
            "phone": phone,
            "role": "staff",
        },
    )
    assert cr.status_code == 201, cr.text
    body = cr.json()
    assert body["generated_password"]
    assert body["user"]["role"] == "staff"


def test_role_change_resets_permissions_to_role_defaults():
    u = uuid.uuid4().hex[:8]
    email = f"owner{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ow{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=h).json()[0]["id"]

    phone = f"92{uuid.uuid4().int % 100000000:08d}"
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=h,
        json={"full_name": "Perm User", "phone": phone, "role": "manager"},
    )
    assert cr.status_code == 201, cr.text
    user_id = cr.json()["user"]["id"]

    pr = client.patch(
        f"/v1/businesses/{bid}/users/{user_id}/permissions",
        headers=h,
        json={"permissions": {"reports_access": False, "export_access": False}},
    )
    assert pr.status_code == 200, pr.text
    assert pr.json()["permissions"]["reports_access"] is False

    patch = client.patch(
        f"/v1/businesses/{bid}/users/{user_id}",
        headers=h,
        json={"role": "staff"},
    )
    assert patch.status_code == 200, patch.text

    gr = client.get(f"/v1/businesses/{bid}/users/{user_id}/permissions", headers=h)
    assert gr.status_code == 200, gr.text
    perms = gr.json()["permissions"]
    assert perms["reports_access"] is False
    assert perms["purchase_edit"] is False
    assert perms["stock_edit"] is True

def test_reset_password_revokes_access_and_refresh():
    u = uuid.uuid4().hex[:8]
    email = f"staff{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"st{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    tokens = r.json()
    staff_h = {"Authorization": f"Bearer {tokens['access_token']}"}
    refresh = tokens["refresh_token"]
    bid = client.get("/v1/me/businesses", headers=staff_h).json()[0]["id"]
    me = client.get("/v1/me/profile", headers=staff_h).json()
    staff_id = me["id"]

    # Owner resets this user's password (same user acting as owner of their workspace).
    rr = client.post(
        f"/v1/businesses/{bid}/users/{staff_id}/reset-password",
        headers=staff_h,
    )
    assert rr.status_code == 200, rr.text
    assert rr.json().get("new_password")

    # Old access token must fail.
    bad = client.get("/v1/me/profile", headers=staff_h)
    assert bad.status_code == 401, bad.text

    # Old refresh must fail (token_version bump).
    ref = client.post("/v1/auth/refresh", json={"refresh_token": refresh})
    assert ref.status_code == 401, ref.text


def test_admin_cannot_patch_owner_permissions():
    u = uuid.uuid4().hex[:8]
    owner_email = f"own{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"own{u}", "email": owner_email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    owner_h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=owner_h).json()[0]["id"]
    owner_id = client.get("/v1/me/profile", headers=owner_h).json()["id"]

    phone = f"93{uuid.uuid4().int % 100000000:08d}"
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=owner_h,
        json={"full_name": "Admin User", "phone": phone, "role": "admin"},
    )
    assert cr.status_code == 201, cr.text
    admin_id = cr.json()["user"]["id"]
    # Reset admin password and login as admin
    rp = client.post(
        f"/v1/businesses/{bid}/users/{admin_id}/reset-password",
        headers=owner_h,
    )
    assert rp.status_code == 200, rp.text
    new_pw = rp.json()["new_password"]
    admin_email = cr.json()["user"]["email"]
    # create_user returns login_email on UserCreateOut
    login_email = cr.json().get("login_email") or admin_email
    login = client.post(
        "/v1/auth/login",
        json={"email": login_email, "password": new_pw},
    )
    assert login.status_code == 200, login.text
    admin_h = {"Authorization": f"Bearer {login.json()['access_token']}"}

    pr = client.patch(
        f"/v1/businesses/{bid}/users/{owner_id}/permissions",
        headers=admin_h,
        json={"permissions": {"user_manage": False}},
    )
    assert pr.status_code == 403, pr.text


def test_staff_cannot_view_other_user_activity():
    u = uuid.uuid4().hex[:8]
    r = client.post(
        "/v1/auth/register",
        json={"username": f"ow{u}", "email": f"ow{u}@test.hexa.local", "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    owner_h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    bid = client.get("/v1/me/businesses", headers=owner_h).json()[0]["id"]
    owner_id = client.get("/v1/me/profile", headers=owner_h).json()["id"]

    phone = f"94{uuid.uuid4().int % 100000000:08d}"
    cr = client.post(
        f"/v1/businesses/{bid}/users",
        headers=owner_h,
        json={"full_name": "Staff View", "phone": phone, "role": "staff"},
    )
    assert cr.status_code == 201, cr.text
    staff_id = cr.json()["user"]["id"]
    rp = client.post(
        f"/v1/businesses/{bid}/users/{staff_id}/reset-password",
        headers=owner_h,
    )
    assert rp.status_code == 200, rp.text
    login = client.post(
        "/v1/auth/login",
        json={"email": cr.json()["login_email"], "password": rp.json()["new_password"]},
    )
    assert login.status_code == 200, login.text
    staff_h = {"Authorization": f"Bearer {login.json()['access_token']}"}

    denied = client.get(
        f"/v1/businesses/{bid}/activity-log",
        headers=staff_h,
        params={"user_id": owner_id},
    )
    assert denied.status_code == 403, denied.text
