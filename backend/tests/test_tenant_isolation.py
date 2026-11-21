"""Multi-tenant isolation: two independent client companies must never see or change each other's data.

NOTE: PostgreSQL row-level security is enabled by migration 054 but is NOT an effective control today
(not forced, and the app never sets app.current_business_id; the table owner bypasses it). Isolation
therefore depends entirely on the application checks exercised here.
"""

from __future__ import annotations

import uuid
from datetime import date

import pytest
from fastapi.testclient import TestClient
from jose import jwt

from app.main import app

client = TestClient(app)


class Tenant:
    """One client company: its owner login plus a few resources."""

    def __init__(self, label: str):
        u = uuid.uuid4().hex[:10]
        r = client.post(
            "/v1/auth/register",
            json={"username": f"{label}{u}", "email": f"{label}{u}@test.hexa.local", "password": "testpass12"},
        )
        assert r.status_code == 200, r.text
        self.token = r.json()["access_token"]
        self.h = {"Authorization": f"Bearer {self.token}"}
        self.bid = client.get("/v1/me/businesses", headers=self.h).json()[0]["id"]
        self.base = f"/v1/businesses/{self.bid}"
        self.secret_name = f"SECRET-{label}-{u}"

        cat = client.post(f"{self.base}/item-categories", headers=self.h, json={"name": f"Cat {u}"})
        assert cat.status_code == 201, cat.text
        self.category_id = cat.json()["id"]
        sup = client.post(
            f"{self.base}/suppliers", headers=self.h, json={"name": self.secret_name, "phone": "9000000011"}
        )
        assert sup.status_code == 201, sup.text
        self.supplier_id = sup.json()["id"]
        item = client.post(
            f"{self.base}/catalog-items",
            headers=self.h,
            json={
                "category_id": self.category_id,
                "name": f"{self.secret_name} ITEM",
                "default_unit": "piece",
                "default_supplier_ids": [self.supplier_id],
            },
        )
        assert item.status_code == 201, item.text
        self.item_id = item.json()["id"]
        pur = client.post(
            f"{self.base}/trade-purchases",
            headers=self.h,
            json={
                "purchase_date": date.today().isoformat(),
                "status": "confirmed",
                "supplier_id": self.supplier_id,
                "lines": [
                    {
                        "catalog_item_id": self.item_id,
                        "item_name": f"{self.secret_name} ITEM",
                        "qty": "10",
                        "unit": "piece",
                        "purchase_rate": "100",
                        "landing_cost": "100",
                    }
                ],
            },
        )
        assert pur.status_code in (200, 201), pur.text
        self.purchase_id = pur.json()["id"]


@pytest.fixture(scope="module")
def a() -> Tenant:
    return Tenant("tenanta")


@pytest.fixture(scope="module")
def b() -> Tenant:
    return Tenant("tenantb")


def _ok(r):  # a response that carries data
    return 200 <= r.status_code < 300


# Endpoints a stranger must not be able to read from someone else's business path.
_BUSINESS_GETS = [
    "/catalog-items",
    "/item-categories",
    "/suppliers/{supplier_id}",
    "/brokers",
    "/trade-purchases",
    "/trade-purchases/{purchase_id}",
    "/stock/list",
    "/stock/{item_id}",
    "/users",
    "/notifications",
    "/report-views",
    "/reports/trade-summary",
    "/operations/checklist/today",
    "/search?q=SECRET",
]


@pytest.mark.parametrize("path", _BUSINESS_GETS)
def test_foreign_business_path_is_forbidden(a: Tenant, b: Tenant, path: str):
    """B's valid token against A's business id: always 403, never data."""
    url = a.base + path.format(supplier_id=a.supplier_id, purchase_id=a.purchase_id, item_id=a.item_id)
    r = client.get(url, headers=b.h)
    assert r.status_code == 403, f"{path}: {r.status_code} {r.text[:120]}"


@pytest.mark.parametrize("path", _BUSINESS_GETS[:3] + ["/trade-purchases", "/stock/list"])
def test_unauthenticated_is_rejected(a: Tenant, path: str):
    url = a.base + path.format(supplier_id=a.supplier_id)
    assert client.get(url).status_code in (401, 403)


def test_forged_token_is_rejected(a: Tenant):
    """A token signed with the wrong key must not authenticate, even with a real user id."""
    uid = jwt.get_unverified_claims(a.token)["sub"]
    forged = jwt.encode({"sub": uid, "type": "access"}, "not-the-real-secret-not-the-real-secret", algorithm="HS256")
    r = client.get(f"{a.base}/catalog-items", headers={"Authorization": f"Bearer {forged}"})
    assert r.status_code == 401


def test_foreign_resource_ids_inside_own_business_are_not_found(a: Tenant, b: Tenant):
    """B uses B's business id but A's resource ids: must not read, change or delete them."""
    for path in (
        f"/catalog-items/{a.item_id}",
        f"/suppliers/{a.supplier_id}",
        f"/trade-purchases/{a.purchase_id}",
        f"/stock/{a.item_id}",
    ):
        r = client.get(b.base + path, headers=b.h)
        assert not _ok(r), f"GET {path} leaked across tenants: {r.status_code}"
        assert a.secret_name not in r.text

    patch = client.patch(f"{b.base}/catalog-items/{a.item_id}", headers=b.h, json={"name": "HACKED"})
    assert not _ok(patch)
    patch = client.patch(f"{b.base}/suppliers/{a.supplier_id}", headers=b.h, json={"name": "HACKED"})
    assert not _ok(patch)
    assert not _ok(client.delete(f"{b.base}/catalog-items/{a.item_id}", headers=b.h))
    assert not _ok(client.delete(f"{b.base}/suppliers/{a.supplier_id}", headers=b.h))
    assert not _ok(client.delete(f"{b.base}/trade-purchases/{a.purchase_id}", headers=b.h))


def test_b_cannot_build_a_purchase_from_a_resources(a: Tenant, b: Tenant):
    """Cross-tenant references (A's supplier / A's item inside B's purchase) must be rejected."""
    before = client.get(f"{b.base}/trade-purchases", headers=b.h).json()
    r = client.post(
        f"{b.base}/trade-purchases",
        headers=b.h,
        json={
            "purchase_date": date.today().isoformat(),
            "status": "confirmed",
            "supplier_id": a.supplier_id,
            "lines": [
                {
                    "catalog_item_id": a.item_id,
                    "item_name": "cross tenant",
                    "qty": "1",
                    "unit": "piece",
                    "purchase_rate": "1",
                    "landing_cost": "1",
                }
            ],
        },
    )
    after = client.get(f"{b.base}/trade-purchases", headers=b.h).json()
    assert not _ok(r), f"cross-tenant purchase was accepted: {r.status_code} {r.text[:150]}"
    assert len(after) == len(before)


def test_search_never_returns_other_tenants_data(a: Tenant, b: Tenant):
    for q in (a.secret_name, "SECRET-tenanta"):
        r = client.get(f"{b.base}/search", headers=b.h, params={"q": q})
        assert a.secret_name not in r.text
    for path in ("/catalog-items", "/trade-purchases", "/stock/list?page=1&per_page=50"):
        r = client.get(b.base + path, headers=b.h)
        assert r.status_code == 200, r.text
        assert a.secret_name not in r.text, f"{path} leaked tenant A data to tenant B"


def test_each_tenant_sees_its_own_data(a: Tenant, b: Tenant):
    for t in (a, b):
        items = client.get(f"{t.base}/catalog-items", headers=t.h).json()
        assert any(i["id"] == t.item_id for i in items)
        assert all(not (t is a and i["id"] == b.item_id) for i in items)


def test_a_data_is_unchanged_after_b_attacks(a: Tenant, b: Tenant):
    item = client.get(f"{a.base}/catalog-items/{a.item_id}", headers=a.h)
    assert item.status_code == 200 and item.json()["name"] == f"{a.secret_name} ITEM"
    assert client.get(f"{a.base}/suppliers/{a.supplier_id}", headers=a.h).status_code == 200
    assert client.get(f"{a.base}/trade-purchases/{a.purchase_id}", headers=a.h).status_code == 200


def test_staff_of_one_company_cannot_enter_another(a: Tenant, b: Tenant):
    """An employee account created inside company A has no access to company B."""
    u = uuid.uuid4().hex[:8]
    email = f"staffa{u}@test.hexa.local"
    created = client.post(
        f"{a.base}/users",
        headers=a.h,
        json={"email": email, "phone": f"90000{u[:5]}".replace("a", "1").replace("b", "2").replace("c", "3")
              .replace("d", "4").replace("e", "5").replace("f", "6"),
              "role": "staff", "full_name": "Staff A", "password": "staffpass12"},
    )
    assert created.status_code == 201, created.text
    login = client.post("/v1/auth/login", json={"email": email, "password": "staffpass12"})
    assert login.status_code == 200, login.text
    sh = {"Authorization": f"Bearer {login.json()['access_token']}"}
    # own company: allowed to read stock; other company: forbidden everywhere
    assert client.get(f"{a.base}/stock/list", headers=sh).status_code == 200
    for path in ("/stock/list", "/catalog-items", "/trade-purchases", f"/catalog-items/{b.item_id}"):
        r = client.get(b.base + path, headers=sh)
        assert r.status_code == 403, f"staff of A reached B via {path}: {r.status_code}"
    # and cannot manage users of the other company
    assert client.get(f"{b.base}/users", headers=sh).status_code == 403


def test_b_cannot_repoint_own_purchase_to_a_resources(a: Tenant, b: Tenant):
    """The update path needs the same tenant checks as create."""

    def body(supplier_id: str, item_id: str) -> dict:
        return {
            "purchase_date": date.today().isoformat(),
            "status": "confirmed",
            "supplier_id": supplier_id,
            "force_duplicate": True,
            "lines": [
                {
                    "catalog_item_id": item_id,
                    "item_name": "update check",
                    "qty": "1",
                    "unit": "piece",
                    "purchase_rate": "1",
                    "landing_cost": "1",
                }
            ],
        }

    # Positive control: the very same request with B's OWN supplier and item is accepted, so a rejection
    # below can only be caused by the tenant check and not by a malformed body.
    ok = client.put(f"{b.base}/trade-purchases/{b.purchase_id}", headers=b.h, json=body(b.supplier_id, b.item_id))
    assert ok.status_code == 200, ok.text
    r = client.put(f"{b.base}/trade-purchases/{b.purchase_id}", headers=b.h, json=body(a.supplier_id, a.item_id))
    assert not _ok(r), f"cross-tenant update was accepted: {r.status_code} {r.text[:150]}"
    mine = client.get(f"{b.base}/trade-purchases/{b.purchase_id}", headers=b.h).json()
    assert str(mine["supplier_id"]) == b.supplier_id


def test_other_write_paths_reject_foreign_ids(a: Tenant, b: Tenant):
    """Every other endpoint that takes another record's id must refuse ids from a different company."""
    broker = client.post(f"{a.base}/brokers", headers=a.h, json={"name": "A broker", "phone": "9000000022"})
    assert broker.status_code in (200, 201), broker.text
    broker_a = broker.json()["id"]
    attempts = {
        "create item with foreign category": client.post(
            f"{b.base}/catalog-items", headers=b.h,
            json={"category_id": a.category_id, "name": "x-cat", "default_unit": "piece"}),
        "create item with foreign default supplier": client.post(
            f"{b.base}/catalog-items", headers=b.h,
            json={"category_id": b.category_id, "name": "x-sup", "default_unit": "piece",
                  "default_supplier_ids": [a.supplier_id]}),
        "move own item to foreign category": client.patch(
            f"{b.base}/catalog-items/{b.item_id}", headers=b.h, json={"category_id": a.category_id}),
        "set foreign default supplier on own item": client.patch(
            f"{b.base}/catalog-items/{b.item_id}", headers=b.h, json={"default_supplier_ids": [a.supplier_id]}),
        "create supplier with foreign broker": client.post(
            f"{b.base}/suppliers", headers=b.h,
            json={"name": "x", "phone": "9000000033", "broker_ids": [broker_a]}),
        "link own supplier to foreign broker": client.patch(
            f"{b.base}/suppliers/{b.supplier_id}", headers=b.h, json={"broker_ids": [broker_a]}),
        "opening stock on foreign item": client.post(
            f"{b.base}/stock/{a.item_id}/opening-stock", headers=b.h, json={"qty": 5}),
        "physical count on foreign item": client.post(
            f"{b.base}/stock/{a.item_id}/physical-count", headers=b.h, json={"counted_qty": 3}),
        "payment on foreign purchase": client.patch(
            f"{b.base}/trade-purchases/{a.purchase_id}/payment", headers=b.h, json={"paid_amount": 1}),
    }
    for action in ("arrive", "verify", "commit-stock", "cancel"):
        attempts[f"{action} on foreign purchase"] = client.post(
            f"{b.base}/trade-purchases/{a.purchase_id}/{action}", headers=b.h, json={})
    users = client.get(f"{a.base}/users", headers=a.h).json()
    if users:
        uid = users[0]["id"]
        attempts["read foreign user"] = client.get(f"{b.base}/users/{uid}", headers=b.h)
        attempts["reset password of foreign user"] = client.post(
            f"{b.base}/users/{uid}/reset-password", headers=b.h, json={})
    leaked = {k: v.status_code for k, v in attempts.items() if _ok(v)}
    assert not leaked, f"cross-tenant actions were accepted: {leaked}"
    # and company A's purchase is still unpaid / unchanged
    mine = client.get(f"{a.base}/trade-purchases/{a.purchase_id}", headers=a.h).json()
    assert float(mine.get("paid_amount") or 0) == 0


# Exports, backup/restore, live updates and owner tools must be unreachable for another company's token.
_SURFACE_GETS = [
    "/exports/stock-inventory.xlsx", "/exports/purchases-month.pdf", "/exports/backup/export", "/exports/backup/logs",
    "/realtime/events", "/realtime/recent", "/damage-reports/pending-count", "/stock-audits", "/stock-audits/active",
    "/activity-log", "/staff/tasks", "/staff/performance-summary", "/owner/dashboard", "/owner/whatsapp-deliveries",
    "/settings/credentials", "/operations/usage/today", "/operations/snapshots", "/reports/home-overview",
    "/reports/trade-items", "/stock/barcode/index",
]
_SURFACE_POSTS = [
    "/exports/backup", "/exports/backup/run", "/exports/restore/dry-run", "/exports/restore/commit",
    "/notifications/mark-all-read",
]


@pytest.mark.parametrize("path", _SURFACE_GETS)
def test_exports_realtime_and_owner_tools_reject_foreign_company(a: Tenant, b: Tenant, path: str):
    r = client.get(a.base + path, headers=b.h)
    assert r.status_code == 403, f"GET {path}: {r.status_code}"


@pytest.mark.parametrize("path", _SURFACE_POSTS)
def test_backup_restore_and_bulk_actions_reject_foreign_company(a: Tenant, b: Tenant, path: str):
    r = client.post(a.base + path, headers=b.h, json={})
    assert r.status_code == 403, f"POST {path}: {r.status_code}"


def test_public_item_page_exposes_no_prices_or_suppliers_and_needs_the_token(a: Tenant):
    """Public QR pages are open by design; they may show stock facts only, behind an unguessable token."""
    tok = client.get(f"{a.base}/catalog-items/{a.item_id}", headers=a.h).json()["public_token"]
    assert len(tok) >= 32
    d = client.get(f"/public/items/{tok}.json").json()
    risky = [k for k in d if any(w in k.lower() for w in
             ("price", "rate", "cost", "supplier", "broker", "profit", "landing", "selling", "phone", "gst"))]
    assert not risky, f"public page exposes sensitive fields: {risky}"
    assert a.supplier_id not in str(d)  # no supplier reference of any kind
    assert client.get("/public/items/" + "0" * 32 + ".json").status_code == 404
