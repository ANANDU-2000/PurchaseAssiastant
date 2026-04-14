"""In-app assistant: intent routing, preview/confirm via entry pipeline, grounded analytics replies."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.models import Entry, EntryLineItem, Supplier
from app.schemas.entries import EntryCreateRequest
from app.services.entry_create_pipeline import commit_create_entry_confirmed, prepare_create_entry_preview
from app.services.intent_stub import stub_intent_from_text
from app.services.llm_intent import extract_intent_json
from app.services.whatsapp_action_resolution import build_entry_create_request, ist_today


def _month_to_date_range() -> tuple[date, date]:
    today = ist_today()
    start = date(today.year, today.month, 1)
    return start, today


def _parse_float(v: object) -> float | None:
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip().replace(",", "")
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _intent_data_to_transaction_dict(data: dict[str, Any]) -> dict[str, Any]:
    """Map LLM / stub intent `data` into keys expected by `build_entry_create_request`."""
    item = data.get("item")
    unit_raw = (data.get("unit") or data.get("unit_type") or "kg").strip().lower()
    if unit_raw in ("box",):
        unit = "box"
    elif unit_raw in ("piece", "pc"):
        unit = "piece"
    elif unit_raw in ("bag", "bags"):
        unit = "bag"
    else:
        unit = "kg"

    qty: float | None = _parse_float(data.get("qty"))
    if qty is None:
        qty = _parse_float(data.get("qty_kg"))
    if qty is None and unit == "bag":
        bags = _parse_float(data.get("bags"))
        kgpb = _parse_float(data.get("kg_per_bag"))
        if bags is not None and kgpb is not None:
            qty = bags * kgpb

    buy = (
        _parse_float(data.get("buy_price"))
        or _parse_float(data.get("purchase_price_per_bag"))
        or _parse_float(data.get("purchase_price"))
    )
    land = (
        _parse_float(data.get("landing_cost"))
        or _parse_float(data.get("landed_cost_per_bag"))
        or _parse_float(data.get("land"))
    )

    out: dict[str, Any] = {
        "item": item,
        "qty": qty,
        "unit": unit,
        "buy_price": buy,
        "landing_cost": land,
        "selling_price": _parse_float(data.get("selling_price") or data.get("selling_price_per_kg")),
        "supplier_name": data.get("supplier") or data.get("supplier_name"),
        "broker_name": data.get("broker") or data.get("broker_name"),
        "entry_date": data.get("entry_date") or data.get("date"),
    }
    return out


def _is_affirmation(text: str) -> bool:
    t = text.strip().lower()
    return t in ("yes", "y", "ok", "okay", "confirm", "save", "হ্যাঁ", "ஆம்") or t.startswith("yes ")


def _is_negation(text: str) -> bool:
    t = text.strip().lower()
    return t in ("no", "n", "cancel", "stop", "abort")


def _detect_help(text: str) -> bool:
    t = text.strip().lower()
    return t in ("help", "?", "hi", "hello", "hey") or t.startswith("help ")


def _detect_query_intent(text: str) -> bool:
    t = text.lower()
    keys = (
        "profit",
        "total",
        "report",
        "summary",
        "best supplier",
        "top item",
        "how much",
        "this month",
        "analytics",
        "insight",
    )
    return any(k in t for k in keys) or "?" in t


def _bf(business_id: uuid.UUID, from_date: date, to_date: date):
    return (
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
    )


async def _grounded_query_reply(
    db: AsyncSession,
    business_id: uuid.UUID,
    text: str,
) -> str:
    """Short reply using same aggregates as analytics summary + home insights (month-to-date)."""
    del text
    fd, td = _month_to_date_range()
    bf = _bf(business_id, fd, td)

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
    cnt = await db.execute(select(func.count(Entry.id.distinct())).where(*bf))
    total_purchase = float(purchase.scalar() or 0)
    total_profit = float(profit.scalar() or 0)
    purchase_count = int(cnt.scalar() or 0)

    q_top = (
        select(
            EntryLineItem.item_name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(*bf)
        .group_by(EntryLineItem.item_name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    top = await db.execute(q_top)
    trow = top.first()
    top_name = trow[0] if trow else None
    top_profit = float(trow[1]) if trow else None

    q_best_sup = (
        select(
            Supplier.name,
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .join(Supplier, Supplier.id == Entry.supplier_id)
        .where(*bf, Entry.supplier_id.isnot(None))
        .group_by(Supplier.id, Supplier.name)
        .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        .limit(1)
    )
    bs = await db.execute(q_best_sup)
    bs_row = bs.first()
    best_supplier_name = bs_row[0] if bs_row else None
    best_supplier_profit = float(bs_row[1]) if bs_row else None

    lines: list[str] = [
        f"Period {fd.isoformat()} → {td.isoformat()}: "
        f"profit ₹{total_profit:,.0f}, purchases ₹{total_purchase:,.0f}, {purchase_count} entries."
    ]
    if top_name:
        lines.append(f"Top item: {top_name} (profit ₹{top_profit or 0:,.0f}).")
    if best_supplier_name:
        lines.append(
            f"Best supplier: {best_supplier_name} (profit ₹{best_supplier_profit or 0:,.0f})."
        )
    if purchase_count == 0:
        lines.append("No entries this month yet — add a purchase from Entries or chat.")
    return "\n".join(lines)


async def run_app_assistant_turn(
    *,
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    message: str,
    settings: Settings,
    preview_token: str | None,
    entry_draft: dict[str, Any] | None,
) -> dict[str, Any]:
    """
    Returns dict matching AppAssistantChatResponse fields (flat).
    """
    text = message.strip()

    # Confirm / cancel using prior preview
    if preview_token and entry_draft and _is_affirmation(text):
        try:
            body = EntryCreateRequest.model_validate(entry_draft)
        except Exception as e:  # noqa: BLE001
            return {
                "reply": f"Invalid saved draft: {e!s}. Start a new purchase message.",
                "intent": "clarify",
                "preview_token": None,
                "entry_draft": None,
                "saved_entry": None,
                "missing_fields": [],
            }
        body = body.model_copy(update={"confirm": True, "preview_token": preview_token})
        try:
            out = await commit_create_entry_confirmed(
                db, business_id, user_id, body, source="app_chat"
            )
            return {
                "reply": f"Saved entry #{str(out.id)[:8]}…",
                "intent": "confirm_saved",
                "preview_token": None,
                "entry_draft": None,
                "saved_entry": out.model_dump(mode="json"),
                "missing_fields": [],
            }
        except Exception as e:  # noqa: BLE001
            return {
                "reply": str(e) if str(e) else "Could not save. Preview again or fix fields.",
                "intent": "clarify",
                "preview_token": preview_token,
                "entry_draft": entry_draft,
                "saved_entry": None,
                "missing_fields": [],
            }

    if preview_token and entry_draft and _is_negation(text):
        return {
            "reply": "Cancelled. Send a new purchase when ready.",
            "intent": "cancelled",
            "preview_token": None,
            "entry_draft": None,
            "saved_entry": None,
            "missing_fields": [],
        }

    if _detect_help(text) and len(text) < 40:
        return {
            "reply": (
                "Harisree assistant\n"
                "• Add purchase: e.g. “100 kg rice from Surag, buy ₹700 land ₹720”\n"
                "• I’ll show a preview — reply YES to save.\n"
                "• Ask: profit this month, best supplier, top item."
            ),
            "intent": "help",
            "preview_token": None,
            "entry_draft": None,
            "saved_entry": None,
            "missing_fields": [],
        }

    if _detect_query_intent(text):
        reply = await _grounded_query_reply(db, business_id, text)
        return {
            "reply": reply,
            "intent": "query",
            "preview_token": None,
            "entry_draft": None,
            "saved_entry": None,
            "missing_fields": [],
        }

    # Parse purchase intent (LLM or stub via ai_chat router helpers)
    llm = await extract_intent_json(user_text=text, settings=settings, db=db)
    if llm is not None:
        intent = str(llm.get("intent") or "create_entry")
        data = llm.get("data") if isinstance(llm.get("data"), dict) else {}
        llm_missing: list[str] = [
            str(x) for x in (llm.get("missing_fields") or []) if x is not None
        ]
        reply_text = str(llm.get("reply_text") or "").strip()

        if intent == "query_summary":
            reply = await _grounded_query_reply(db, business_id, text)
            return {
                "reply": reply,
                "intent": "query",
                "preview_token": None,
                "entry_draft": None,
                "saved_entry": None,
                "missing_fields": [],
            }

        if intent in ("update_entry", "delete_entry"):
            return {
                "reply": "To edit or delete entries, use the Entries tab in the app.",
                "intent": "clarify",
                "preview_token": None,
                "entry_draft": None,
                "saved_entry": None,
                "missing_fields": [],
            }

        tx = _intent_data_to_transaction_dict(data)
        req, miss = await build_entry_create_request(db, business_id, tx)
        combine_miss = list(dict.fromkeys((miss or []) + llm_missing))
        if req is None or (miss and len(miss) > 0):
            return {
                "reply": reply_text
                or "Need: "
                + ", ".join(combine_miss or ["more detail (qty, buy, land, item)"]),
                "intent": "clarify",
                "preview_token": None,
                "entry_draft": None,
                "saved_entry": None,
                "missing_fields": combine_miss,
            }

        content, normalized = await prepare_create_entry_preview(db, business_id, user_id, req)
        token = content.get("preview_token")
        draft = normalized.model_dump(mode="json")
        lines = content.get("lines") or []
        prev_lines = "\n".join(
            f"• {li.get('item_name')}: {li.get('qty')} {li.get('unit')} buy ₹{li.get('buy_price')} land ₹{li.get('landing_cost')}"
            for li in lines[:5]
        )
        reply = (
            f"Preview (not saved):\n{prev_lines}\n\n"
            f"Reply YES to save, or NO to cancel."
        )
        return {
            "reply": reply,
            "intent": "add_purchase_preview",
            "preview_token": token,
            "entry_draft": draft,
            "saved_entry": None,
            "missing_fields": [],
        }

    # Stub path (no LLM)
    data, stub_missing = stub_intent_from_text(text)
    tx = _intent_data_to_transaction_dict(data)
    req, miss = await build_entry_create_request(db, business_id, tx)
    if req is None or miss:
        return {
            "reply": "I need: "
            + ", ".join(stub_missing or miss or ["item", "qty", "buy_price", "landing_cost"])
            + ". Example: 100 kg rice buy ₹700 land ₹720",
            "intent": "clarify",
            "preview_token": None,
            "entry_draft": None,
            "saved_entry": None,
            "missing_fields": list(dict.fromkeys((miss or []) + stub_missing)),
        }

    content, normalized = await prepare_create_entry_preview(db, business_id, user_id, req)
    token = content.get("preview_token")
    draft = normalized.model_dump(mode="json")
    lines = content.get("lines") or []
    prev_lines = "\n".join(
        f"• {li.get('item_name')}: {li.get('qty')} {li.get('unit')} buy ₹{li.get('buy_price')} land ₹{li.get('landing_cost')}"
        for li in lines[:5]
    )
    reply = f"Preview (not saved):\n{prev_lines}\n\nReply YES to save, or NO to cancel."
    return {
        "reply": reply,
        "intent": "add_purchase_preview",
        "preview_token": token,
        "entry_draft": draft,
        "saved_entry": None,
        "missing_fields": [],
    }
