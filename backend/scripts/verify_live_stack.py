#!/usr/bin/env python3
"""Call a running API to verify calculations (analytics vs entries) + AI + optional voice stub."""

from __future__ import annotations

import sys
from datetime import date, timedelta

import httpx

EMAIL = "demo.fake@hexa.local"
PASSWORD = "DemoFake2026!"


def main() -> None:
    base = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8001").rstrip("/")
    today = date.today()
    fd = today - timedelta(days=120)

    with httpx.Client(timeout=60.0) as c:
        hr = c.get(f"{base}/health")
        print("--- health ---", hr.status_code, hr.json() if hr.status_code == 200 else hr.text[:120])
        if hr.status_code != 200:
            print("Hint: start the API first (uvicorn) so /health and login succeed.")
            sys.exit(1)

        r = c.post(f"{base}/v1/auth/login", json={"email": EMAIL, "password": PASSWORD})
        if r.status_code != 200:
            print("LOGIN_FAIL", r.status_code, r.text[:300])
            print(
                "Hint: register a user (POST /v1/auth/register) or sign in with an "
                "existing account; DATABASE_URL must point at your Supabase/Postgres."
            )
            sys.exit(1)
        tok = r.json()["access_token"]
        h = {"Authorization": f"Bearer {tok}"}
        bid = c.get(f"{base}/v1/me/businesses", headers=h).json()[0]["id"]

        # Analytics
        ar = c.get(
            f"{base}/v1/businesses/{bid}/analytics/summary",
            headers=h,
            params={"from": fd.isoformat(), "to": today.isoformat()},
        )
        ar.raise_for_status()
        a = ar.json()

        # Entries (same window)
        er = c.get(
            f"{base}/v1/businesses/{bid}/entries",
            headers=h,
            params={"from": fd.isoformat(), "to": today.isoformat()},
        )
        er.raise_for_status()
        items = er.json().get("items", [])

        manual_purchase = 0.0
        manual_profit = 0.0
        for e in items:
            ed = date.fromisoformat(e["entry_date"][:10])
            if ed < fd or ed > today:
                continue
            for li in e.get("lines", []):
                q = float(li["qty"])
                bp = float(li["buy_price"])
                manual_purchase += q * bp
                if li.get("profit") is not None:
                    manual_profit += float(li["profit"])

        diff_p = abs(manual_purchase - float(a["total_purchase"]))
        diff_pr = abs(manual_profit - float(a["total_profit"]))
        ok_calc = diff_p < 0.02 and diff_pr < 0.02

        print("--- analytics/summary ---")
        print(a)
        print("--- manual sum from GET /entries lines (same date filter) ---")
        print(
            "manual_purchase",
            round(manual_purchase, 4),
            "manual_profit",
            round(manual_profit, 4),
        )
        print("match_analytics", ok_calc, "diff_purchase", diff_p, "diff_profit", diff_pr)

        # AI intent (stub)
        ir = c.post(
            f"{base}/v1/businesses/{bid}/ai/intent",
            headers=h,
            json={"text": "10 bags rice 25kg per bag landed 1800 selling 55"},
        )
        print("--- ai/intent ---", ir.status_code, ir.json() if ir.status_code == 200 else ir.text[:200])

        # Voice stub (403 unless ENABLE_VOICE=true on server)
        vr = c.post(
            f"{base}/v1/businesses/{bid}/media/voice",
            headers=h,
            json={"audio_base64": "AAAA"},
        )
        print("--- media/voice ---", vr.status_code, vr.json() if vr.headers.get("content-type", "").startswith("application/json") else vr.text[:120])

        if not ok_calc:
            sys.exit(2)
        if ir.status_code != 200:
            sys.exit(3)
        print("--- verify_live_stack: OK ---")


if __name__ == "__main__":
    main()
