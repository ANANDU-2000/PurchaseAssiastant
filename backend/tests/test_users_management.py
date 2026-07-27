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
