"""Inbound WhatsApp message handling: query mode, preview/confirm entry, Redis state."""

from __future__ import annotations

import re
import uuid
from datetime import date, datetime
from typing import Any

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.models import Entry, EntryLineItem, Membership, Supplier, User
from app.schemas.entries import EntryCreateRequest, EntryLineInput
from app.services.dialog360_send import send_text_message
from app.services.entry_write import persist_confirmed_entry
from app.services.billing_entitlements import assert_whatsapp_entitled
from app.services.feature_flags import is_whatsapp_bot_enabled
from app.services.whatsapp_state import get_state, set_state


def _digits(p: str) -> str:
    return "".join(c for c in p if c.isdigit())


async def find_user_by_chat_phone(db: AsyncSession, phone_from_provider: str) -> User | None:
    """Match WhatsApp `from` to a User.phone (digits / +prefix tolerant)."""
    d = _digits(phone_from_provider)
    if not d:
        return None
    r = await db.execute(select(User))
    for u in r.scalars().all():
        ud = _digits(u.phone)
        if ud == d or (len(d) >= 10 and ud.endswith(d[-10:])):
            return u
    return None


async def primary_business_id(db: AsyncSession, user_id: uuid.UUID) -> uuid.UUID | None:
    q = await db.execute(
        select(Membership.business_id)
        .where(Membership.user_id == user_id)
        .order_by(Membership.created_at.asc())
        .limit(1)
    )
    row = q.first()
    return row[0] if row else None


def _month_date_filter(business_id: uuid.UUID):
    """MTD inclusive: first of month → today."""
    today = date.today()
    start = date(today.year, today.month, 1)
    return (
        Entry.business_id == business_id,
        Entry.entry_date >= start,
        Entry.entry_date <= today,
    )


async def _today_summary(db: AsyncSession, business_id: uuid.UUID) -> str:
    today = date.today()
    bf = (
        Entry.business_id == business_id,
        Entry.entry_date == today,
    )
    purchase = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.qty * EntryLineItem.buy_price), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
    )
    profit = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.profit), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
    )
    p = float(purchase.scalar() or 0)
    pr = float(profit.scalar() or 0)
    margin = (pr / p * 100) if p > 0 else 0.0
    return (
        f"📅 *Today*\n_{today.strftime('%b %d, %Y')}_\n\n"
        f"🛒 Purchase: ₹{p:,.0f}\n"
        f"📈 Profit: ₹{pr:,.0f} ({margin:.1f}%)\n\n"
        f"{'✅ Good margin!' if margin > 10 else '⚠️ Low margin — check your costs'}"
    )


async def _month_summary(db: AsyncSession, business_id: uuid.UUID) -> str:
    today = date.today()
    start = date(today.year, today.month, 1)
    bf = _month_date_filter(business_id)
    purchase = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.qty * EntryLineItem.buy_price), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
    )
    profit = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.profit), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
    )
    p = float(purchase.scalar() or 0)
    pr = float(profit.scalar() or 0)
    margin = (pr / p * 100) if p > 0 else 0.0
    return (
        f"📊 *This Month Overview*\n"
        f"_{start.strftime('%b %d')} → {today.strftime('%b %d, %Y')}_\n\n"
        f"🛒 Purchase: ₹{p:,.0f}\n"
        f"📈 Profit: ₹{pr:,.0f} ({margin:.1f}%)\n\n"
        f"{'✅ Good margin!' if margin > 10 else '⚠️ Low margin — check your costs'}"
    )


def _wants_today_overview(text: str, low: str) -> bool:
    if "ഇന്ന്" in text:
        return True
    if low in ("today", "daily"):
        return True
    return False


def _wants_month_overview(text: str, low: str) -> bool:
    """Malayalam / English keywords → month summary."""
    if low in ("overview", "summary", "stats", "report") or low == "?":
        return True
    if "overview" in low or "report" in low:
        return True
    if "ഈ മാസം" in text:
        return True
    return False


async def _best_supplier_overall(db: AsyncSession, business_id: uuid.UUID) -> str:
    bf = _month_date_filter(business_id)
    q = await db.execute(
        select(Supplier.name, func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"))
        .select_from(Supplier)
        .join(Entry, Entry.supplier_id == Supplier.id)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(*bf, Entry.supplier_id.isnot(None))
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    row = q.first()
    if not row or float(row[1] or 0) == 0:
        return "🏪 *Best supplier*\n_No purchases with a supplier this month yet._"
    name, tp = row[0], float(row[1] or 0)
    return f"🏪 *Top supplier (this month)*\n*{name}* — profit ₹{tp:,.0f}"


async def _best_supplier_for_item(db: AsyncSession, business_id: uuid.UUID, item_fragment: str) -> str:
    frag = item_fragment.strip()
    if len(frag) < 2:
        return "Send: *best rice* (item name) to see which supplier did best on that item."
    bf = _month_date_filter(business_id)
    like = f"%{frag}%"
    q = await db.execute(
        select(Supplier.name, func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"))
        .select_from(Supplier)
        .join(Entry, Entry.supplier_id == Supplier.id)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(*bf, Entry.supplier_id.isnot(None), EntryLineItem.item_name.ilike(like))
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    row = q.first()
    if not row or float(row[1] or 0) == 0:
        return f"🔍 *Best supplier for “{frag}”*\n_No matching lines this month — check spelling or add purchases._"
    name, tp = row[0], float(row[1] or 0)
    return f"🔍 *Best for “{frag}”*\n*{name}* — profit ₹{tp:,.0f} (this month)"


def _parse_entry_text(text: str) -> EntryCreateRequest | None:
    """
    Parse multiline key:value draft. Required keys: item, qty, unit, buy, land (aliases allowed).
    Optional: date (YYYY-MM-DD).
    """
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
        confirm=True,
        lines=[line],
    )


def _preview_lines(body: EntryCreateRequest) -> str:
    li = body.lines[0]
    return (
        "Preview HEXA entry\n"
        f"Date: {body.entry_date.isoformat()}\n"
        f"Item: {li.item_name}\n"
        f"Qty: {li.qty} {li.unit}\n"
        f"Buy: ₹{li.buy_price:,.2f}\n"
        f"Landing: ₹{li.landing_cost:,.2f}\n\n"
        "Reply YES to save or NO to cancel."
    )


def _serialize_draft(body: EntryCreateRequest) -> dict[str, Any]:
    return {
        "entry_date": body.entry_date.isoformat(),
        "lines": [
            {
                "item_name": li.item_name,
                "category": li.category,
                "qty": li.qty,
                "unit": li.unit,
                "buy_price": li.buy_price,
                "landing_cost": li.landing_cost,
                "selling_price": li.selling_price,
            }
            for li in body.lines
        ],
    }


def _draft_from_state(data: dict[str, Any]) -> EntryCreateRequest:
    li = data["lines"][0]
    line = EntryLineInput(
        item_name=li["item_name"],
        category=li.get("category"),
        qty=float(li["qty"]),
        unit=li["unit"],
        buy_price=float(li["buy_price"]),
        landing_cost=float(li["landing_cost"]),
        selling_price=float(li["selling_price"]) if li.get("selling_price") is not None else None,
    )
    return EntryCreateRequest(
        entry_date=date.fromisoformat(str(data["entry_date"])[:10]),
        supplier_id=None,
        broker_id=None,
        invoice_no=None,
        transport_cost=None,
        commission_amount=None,
        confirm=True,
        lines=[line],
    )


_QUERY_RE = re.compile(r"(?P<item>.+?)\s+(?P<price>\d+(?:\.\d+)?)\s*(?:ok|okay|good|fine)\??", re.I)


async def handle_inbound_text(
    *,
    settings: Settings,
    db: AsyncSession,
    phone_from: str,
    text: str | None,
    message_id: str | None,
) -> dict[str, Any]:
    """Main handler after signature verification and JSON parse."""
    to_digits = _digits(phone_from)
    if not text:
        return {"ok": True, "handled": False, "reason": "no_text"}

    user = await find_user_by_chat_phone(db, phone_from)
    if user is None:
        await send_text_message(
            settings,
            db,
            to_e164=to_digits,
            body="This WhatsApp number is not linked to a HEXA account. Sign in with the same phone in the app first.",
        )
        return {"ok": True, "handled": True, "reason": "unknown_user"}

    biz = await primary_business_id(db, user.id)
    if biz is None:
        await send_text_message(settings, db, to_e164=to_digits, body="No business workspace found. Open the HEXA app to finish setup.")
        return {"ok": True, "handled": True, "reason": "no_business"}

    try:
        await assert_whatsapp_entitled(db, biz, settings)
    except HTTPException as e:
        await send_text_message(
            settings,
            db,
            to_e164=to_digits,
            body=str(e.detail),
        )
        return {"ok": True, "handled": True, "reason": "whatsapp_billing"}

    if not await is_whatsapp_bot_enabled(db, settings):
        await send_text_message(
            settings,
            db,
            to_e164=to_digits,
            body="HEXA WhatsApp automation is turned off for this server. Use the mobile app or ask your admin to re-enable the bot.",
        )
        return {"ok": True, "handled": True, "reason": "whatsapp_bot_disabled"}

    state = await get_state(settings, to_digits) or {"phase": "idle"}
    t = text.strip()
    low = t.lower()

    # --- pending confirm ---
    if state.get("phase") == "pending_confirm" and isinstance(state.get("draft"), dict):
        if low in ("yes", "y", "ok", "save", "confirm", "haan"):
            try:
                body = _draft_from_state(state["draft"])
                await persist_confirmed_entry(
                    db,
                    business_id=biz,
                    user_id=user.id,
                    body=body,
                    source="whatsapp",
                )
            except Exception as e:  # noqa: BLE001
                await send_text_message(
                    settings,
                    db,
                    to_e164=to_digits,
                    body=f"Could not save entry: {e!s}. Fix the draft and try again.",
                )
                return {"ok": False, "error": str(e)}
            state = {"phase": "idle"}
            await set_state(settings, to_digits, state)
            await send_text_message(settings, db, to_e164=to_digits, body="Saved in HEXA.")
            return {"ok": True, "handled": True, "saved": True}

        if low in ("no", "n", "cancel", "stop"):
            await set_state(settings, to_digits, {"phase": "idle"})
            await send_text_message(settings, db, to_e164=to_digits, body="Cancelled. Send a new draft when ready.")
            return {"ok": True, "handled": True, "cancelled": True}

        await send_text_message(
            settings,
            db,
            to_e164=to_digits,
            body="Reply YES to save the preview or NO to cancel.",
        )
        return {"ok": True, "handled": True, "prompt": True}

    # --- query: today / month overview ---
    if _wants_today_overview(t, low):
        msg = await _today_summary(db, biz)
        await send_text_message(settings, db, to_e164=to_digits, body=msg)
        return {"ok": True, "handled": True, "query": "today"}

    if _wants_month_overview(t, low):
        msg = await _month_summary(db, biz)
        await send_text_message(settings, db, to_e164=to_digits, body=msg)
        return {"ok": True, "handled": True, "query": "overview"}

    # --- best supplier (this month) ---
    if low == "best supplier" or low == "top supplier" or "best supplier" in low:
        body = await _best_supplier_overall(db, biz)
        await send_text_message(settings, db, to_e164=to_digits, body=body)
        return {"ok": True, "handled": True, "query": "best_supplier"}

    if low.startswith("best ") and len(low) > 5:
        rest = low[5:].strip()
        if rest and rest != "supplier":
            body = await _best_supplier_for_item(db, biz, rest)
            await send_text_message(settings, db, to_e164=to_digits, body=body)
            return {"ok": True, "handled": True, "query": "best_supplier_item"}

    # --- quick price check: "Oil 1200 ok?" ---
    m = _QUERY_RE.match(t.strip())
    if m:
        item = m.group("item").strip()
        price = float(m.group("price"))
        # lightweight message — full PIP is available in app; keep short
        await send_text_message(
            settings,
            db,
            to_e164=to_digits,
            body=(
                f"Noted: {item} @ ₹{price:,.2f}. Open the app Price Intelligence for full range & trend.\n"
                "To record a purchase, send a multiline draft (item/qty/unit/buy/land)."
            ),
        )
        return {"ok": True, "handled": True, "query": "price_check"}

    # --- new draft ---
    parsed = _parse_entry_text(t)
    if parsed:
        await set_state(
            settings,
            to_digits,
            {
                "phase": "pending_confirm",
                "draft": _serialize_draft(parsed),
                "updated_at": datetime.utcnow().isoformat() + "Z",
            },
        )
        await send_text_message(settings, db, to_e164=to_digits, body=_preview_lines(parsed))
        return {"ok": True, "handled": True, "preview": True}

    await send_text_message(
        settings,
        db,
        to_e164=to_digits,
        body=(
            "HEXA WhatsApp\n"
            "• *OVERVIEW* or *REPORT* — this month.\n"
            "• *TODAY* — today's totals.\n"
            "• *BEST SUPPLIER* — top supplier (MTD).\n"
            "• *BEST rice* — best supplier for an item name.\n"
            "• To add a purchase, send:\n"
            "item: …\n"
            "qty: …\n"
            "unit: kg|box|piece\n"
            "buy: …\n"
            "land: …\n"
            "date: YYYY-MM-DD (optional)\n"
            "Then reply YES to save."
        ),
    )
    return {"ok": True, "handled": True, "help": True}
