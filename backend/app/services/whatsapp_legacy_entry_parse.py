"""Legacy multiline key:value entry parser (used as fallback)."""

from __future__ import annotations

from datetime import date

from app.schemas.entries import EntryCreateRequest, EntryLineInput


def parse_multiline_entry_create_request(text: str) -> EntryCreateRequest | None:
    raw_lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if not raw_lines:
        return None
    kv: dict[str, str] = {}
    for ln in raw_lines:
        if ":" not in ln:
            continue
        k, v = ln.split(":", 1)
        key = k.strip().lower().replace(" ", "_")
        kv[key] = v.strip()

    def pick(*names: str) -> str | None:
        for n in names:
            if n in kv and kv[n]:
                return kv[n]
        return None

    item = pick("item", "name", "product")
    qty_s = pick("qty", "quantity")
    unit = (pick("unit") or "").lower()
    buy_s = pick("buy", "buy_price", "bp", "rate")
    land_s = pick("land", "landing", "landing_cost", "lc", "landed")
    date_s = pick("date", "entry_date")

    if not all([item, qty_s, unit, buy_s, land_s]):
        return None
    if unit not in ("kg", "box", "piece"):
        return None
    try:
        qty = float(qty_s.replace(",", ""))
        buy = float(buy_s.replace(",", ""))
        land = float(land_s.replace(",", ""))
    except ValueError:
        return None
    if qty <= 0 or buy < 0 or land < 0:
        return None

    ed = date.today()
    if date_s:
        try:
            ed = date.fromisoformat(date_s[:10])
        except ValueError:
            ed = date.today()

    line = EntryLineInput(
        item_name=item,
        category=None,
        qty=qty,
        unit=unit,  # type: ignore[arg-type]
        buy_price=buy,
        landing_cost=land,
        selling_price=None,
    )
    return EntryCreateRequest(
        entry_date=ed,
        supplier_id=None,
        broker_id=None,
        invoice_no=None,
        transport_cost=None,
        commission_amount=None,
        confirm=False,
        lines=[line],
    )
