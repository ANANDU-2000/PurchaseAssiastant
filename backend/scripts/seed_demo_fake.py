#!/usr/bin/env python3
"""
Load fake demo data via the real HTTP API (same paths the Flutter app uses).

Prerequisites: backend running with a DB whose schema matches current models (see Alembic / recreate DB).
Example (fresh SQLite):
  set DATABASE_URL=sqlite+aiosqlite:///./hexa_demo.db
  set REDIS_URL=
  set CORS_ORIGINS=
  python -m uvicorn app.main:app --host 127.0.0.1 --port 8000

If POST /entries returns 500 on confirm, your DB is likely stale (e.g. missing columns on entry_line_items).
Use a new SQLite file or run migrations, then retry.

Usage:
  python scripts/seed_demo_fake.py
  python scripts/seed_demo_fake.py http://127.0.0.1:8001

Demo login after seed: demo.fake@hexa.local / DemoFake2026!
"""

from __future__ import annotations

import random
import sys
from datetime import date, timedelta

import httpx

# Demo account (fake — for local QA only)
EMAIL = "demo.fake@hexa.local"
USERNAME = "demofake"
PASSWORD = "DemoFake2026!"

CITIES = [
    "Kochi",
    "Kozhikode",
    "Thrissur",
    "Bengaluru",
    "Chennai",
    "Hyderabad",
    "Mumbai",
    "Delhi NCR",
    "Kolkata",
    "Visakhapatnam",
]

ITEMS = [
    ("Rice", "Staples", "kg"),
    ("Sunflower oil", "Grocery", "kg"),
    ("Toor dal", "Staples", "kg"),
    ("Sugar", "Staples", "kg"),
    ("Wheat atta", "Staples", "kg"),
]


def _auth(client: httpx.Client, base: str) -> str:
    r = client.post(
        f"{base}/v1/auth/register",
        json={"email": EMAIL, "username": USERNAME, "password": PASSWORD},
    )
    if r.status_code == 409:
        r = client.post(f"{base}/v1/auth/login", json={"email": EMAIL, "password": PASSWORD})
    r.raise_for_status()
    return r.json()["access_token"]


def _preview_then_save(
    client: httpx.Client,
    base: str,
    headers: dict[str, str],
    business_id: str,
    body: dict,
) -> None:
    r = client.post(
        f"{base}/v1/businesses/{business_id}/entries",
        headers=headers,
        json={**body, "confirm": False},
    )
    r.raise_for_status()
    data = r.json()
    assert data.get("preview") is True
    token = data["preview_token"]
    r2 = client.post(
        f"{base}/v1/businesses/{business_id}/entries",
        headers=headers,
        json={**body, "confirm": True, "preview_token": token},
    )
    if r2.status_code == 409:
        # duplicate line — force save for demo re-runs
        detail = r2.json().get("detail") if r2.headers.get("content-type", "").startswith("application/json") else {}
        if isinstance(detail, dict) and "matching_entry_ids" in detail:
            r2 = client.post(
                f"{base}/v1/businesses/{business_id}/entries",
                headers=headers,
                json={**body, "confirm": True, "preview_token": token, "force_duplicate": True},
            )
    r2.raise_for_status()


def main() -> None:
    base = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
    base = base.rstrip("/")

    with httpx.Client(timeout=120.0) as client:
        r0 = client.get(f"{base}/health")
        r0.raise_for_status()
        print("OK", r0.json())

        token = _auth(client, base)
        headers = {"Authorization": f"Bearer {token}"}

        rb = client.get(f"{base}/v1/me/businesses", headers=headers)
        rb.raise_for_status()
        businesses = rb.json()
        assert businesses, "no business — registration should create one"
        business_id = businesses[0]["id"]
        print("business_id", business_id)

        # --- 100 fake suppliers (idempotent names) ---
        existing = client.get(
            f"{base}/v1/businesses/{business_id}/suppliers",
            headers=headers,
        ).json()
        existing_names = {s["name"] for s in existing}
        created_sup = 0
        for i in range(1, 101):
            name = f"[FAKE] Demo Trader {i:03d}"
            if name in existing_names:
                continue
            loc = random.choice(CITIES)
            phone = f"+9198{random.randint(10000000, 99999999)}"
            r = client.post(
                f"{base}/v1/businesses/{business_id}/suppliers",
                headers=headers,
                json={"name": name, "phone": phone, "location": loc},
            )
            if r.status_code == 201:
                created_sup += 1
            elif r.status_code == 409:
                pass
            else:
                r.raise_for_status()

        suppliers = client.get(
            f"{base}/v1/businesses/{business_id}/suppliers",
            headers=headers,
        ).json()
        fake_suppliers = [s for s in suppliers if s["name"].startswith("[FAKE]")]
        print(f"suppliers total={len(suppliers)} fake_demo={len(fake_suppliers)} newly_created~={created_sup}")

        # --- Categories + catalog items ---
        cats = client.get(
            f"{base}/v1/businesses/{business_id}/item-categories",
            headers=headers,
        ).json()
        cat_by_name = {c["name"]: c["id"] for c in cats}
        for cn in ("Staples", "Grocery"):
            if cn not in cat_by_name:
                r = client.post(
                    f"{base}/v1/businesses/{business_id}/item-categories",
                    headers=headers,
                    json={"name": cn},
                )
                r.raise_for_status()
                cat_by_name[cn] = r.json()["id"]

        catalog_items = client.get(
            f"{base}/v1/businesses/{business_id}/catalog-items",
            headers=headers,
        ).json()
        item_names = {it["name"] for it in catalog_items}
        for item_name, cat_name, _unit in ITEMS:
            if item_name in item_names:
                continue
            r = client.post(
                f"{base}/v1/businesses/{business_id}/catalog-items",
                headers=headers,
                json={
                    "category_id": cat_by_name[cat_name],
                    "name": item_name,
                    "default_unit": "kg",
                },
            )
            if r.status_code == 201:
                pass
            elif r.status_code == 409:
                pass
            else:
                r.raise_for_status()

        # --- Sample purchase entries (spread dates, live totals / analytics) ---
        sup_ids = [s["id"] for s in fake_suppliers[:40]]
        if not sup_ids:
            sup_ids = [s["id"] for s in suppliers[:40]]
        random.seed(42)
        today = date.today()
        entries_to_make = 18
        for n in range(entries_to_make):
            sid = random.choice(sup_ids)
            item_name, cat, unit = random.choice(ITEMS)
            qty = round(random.uniform(10, 500), 2)
            buy = round(random.uniform(28, 120), 2)
            sell = round(buy * random.uniform(1.03, 1.15), 2)
            d = today - timedelta(days=random.randint(0, 45))
            body = {
                "entry_date": d.isoformat(),
                "supplier_id": sid,
                "transport_cost": round(random.uniform(0, 500), 2),
                "lines": [
                    {
                        "item_name": item_name,
                        "category": cat,
                        "qty": qty,
                        "unit": unit,
                        "buy_price": buy,
                        "landing_cost": buy,
                        "selling_price": sell,
                    }
                ],
            }
            try:
                _preview_then_save(client, base, headers, business_id, body)
            except httpx.HTTPStatusError as e:
                print("entry warn:", e.response.status_code, e.response.text[:200])
                raise

        # --- Analytics + AI intent smoke ---
        fd = today - timedelta(days=60)
        rs = client.get(
            f"{base}/v1/businesses/{business_id}/analytics/summary",
            headers=headers,
            params={"from": fd.isoformat(), "to": today.isoformat()},
        )
        rs.raise_for_status()
        print("analytics/summary", rs.json())

        ri = client.post(
            f"{base}/v1/businesses/{business_id}/ai/intent",
            headers=headers,
            json={"text": "50 bags rice 25 kg per bag landed 4200 selling 52 rupees"},
        )
        ri.raise_for_status()
        print("ai/intent", {k: ri.json().get(k) for k in ("intent", "reply_text", "missing_fields")})

        rent = client.get(
            f"{base}/v1/businesses/{business_id}/entries",
            headers=headers,
        )
        rent.raise_for_status()
        ent_count = len(rent.json().get("items", []))
        print("entries listed", ent_count)

    print("--- seed_demo_fake: done ---")


if __name__ == "__main__":
    main()
