"""Transactional WhatsApp orchestration: parse → validate → preview → confirm → execute."""

from __future__ import annotations

import logging
import uuid
from datetime import date
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import Settings
from app.models import Entry, EntryLineItem, User
from app.schemas.entries import EntryCreateRequest, EntryLineInput
from app.services.entry_create_pipeline import commit_create_entry_confirmed, prepare_create_entry_preview
from app.services.entry_patch_service import fetch_last_entry_for_business, patch_first_line_prices
from app.services.feature_flags import is_ai_parsing_enabled
from app.services.llm_intent import extract_whatsapp_transactional_json
from app.services.whatsapp_agent_reply import maybe_polish_whatsapp_reply
from app.services.entry_intent_resolution import (
    build_entry_create_request,
    find_broker_id_by_name,
    find_supplier_id_by_name,
    merge_kv_into_create_data,
)
from app.services.whatsapp_master_write import insert_broker_if_new, insert_catalog_item_if_new, insert_supplier_if_new
from app.services.whatsapp_notify import send_guarded_whatsapp
from app.services.whatsapp_query_service import (
    date_range_to_bounds,
    format_best_supplier_for_item_mtd,
    format_best_supplier_mtd,
    format_broker_commission_mtd,
    format_item_profit,
    format_month_summary,
    format_supplier_compare_top2,
    format_today_summary,
    ist_today_date,
)
from app.services.whatsapp_legacy_entry_parse import parse_multiline_entry_create_request
from app.services.whatsapp_rules import parse_whatsapp_kv_lines, rule_parse_whatsapp
from app.services.whatsapp_state import (
    clear_pending_create_fields,
    get_pending_create_fields,
    get_state,
    set_pending_create_fields,
    set_state,
)

logger = logging.getLogger(__name__)

CONFIDENCE_MIN = 0.38
# When rule-based parse is this confident or higher, skip LLM extraction (cost + drift control).
RULES_SKIP_LLM_MIN_CONFIDENCE = 0.68
ALLOWED_INTENTS = frozenset(
    {
        "create_entry",
        "update_entry",
        "create_supplier",
        "create_broker",
        "create_item",
        "query",
        "out_of_scope",
    }
)


def _out_of_scope_payload() -> dict[str, Any]:
    return {
        "intent": "out_of_scope",
        "data": {},
        "missing_fields": [],
        "clarification_question": None,
        "confidence": 0.15,
        "preview_hint": None,
    }


def merge_rule_and_llm(rules: dict[str, Any] | None, llm: dict[str, Any] | None) -> dict[str, Any]:
    if rules and not llm:
        return rules
    if llm and not rules:
        return llm
    if not rules and not llm:
        return _out_of_scope_payload()
    assert rules and llm
    rc = float(rules.get("confidence") or 0)
    lc = float(llm.get("confidence") or 0)
    ri, li = rules.get("intent"), llm.get("intent")
    if ri == li:
        return rules if rc >= lc else llm
    if rc >= 0.75 and ri != "out_of_scope":
        return rules
    if lc >= 0.72 and li != "out_of_scope":
        return llm
    return rules if rc >= lc else llm


async def merge_parse_async(
    *,
    user_text: str,
    settings: Settings,
    db: AsyncSession,
) -> dict[str, Any]:
    rules = rule_parse_whatsapp(user_text)
    llm: dict[str, Any] | None = None
    skip_llm = bool(
        rules is not None
        and float(rules.get("confidence") or 0) >= RULES_SKIP_LLM_MIN_CONFIDENCE
    )
    if skip_llm:
        logger.info(
            "wa_parse skip_llm rules_conf=%.2f",
            float(rules.get("confidence") or 0),
        )
    elif await is_ai_parsing_enabled(db, settings):
        prov = (settings.ai_provider or "stub").strip().lower()
        if prov != "stub":
            try:
                llm = await extract_whatsapp_transactional_json(
                    user_text=user_text, settings=settings, db=db
                )
            except Exception as e:  # noqa: BLE001
                logger.warning("WhatsApp LLM parse failed: %s", e)
                llm = None
    merged = merge_rule_and_llm(rules, llm)
    logger.info(
        "wa_parse intent=%s conf=%.2f rules=%s llm=%s",
        merged.get("intent"),
        float(merged.get("confidence") or 0),
        bool(rules),
        bool(llm),
    )
    return merged


def _is_yes(t: str) -> bool:
    low = t.lower().strip()
    return low in ("yes", "y", "ok", "save", "confirm", "haan")


def _is_no(t: str) -> bool:
    low = t.lower().strip()
    return low in ("no", "n", "cancel", "stop")


def _wants_force_duplicate(t: str) -> bool:
    low = t.lower().strip()
    if "force" in low and ("yes" in low or "save" in low or "confirm" in low):
        return True
    return low in ("yes force", "force yes", "force save", "force")


def _legacy_draft_to_request(data: dict[str, Any]) -> EntryCreateRequest:
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
        confirm=False,
        lines=[line],
    )


def _format_entry_preview_whatsapp(content: dict[str, Any]) -> str:
    lines = content.get("lines") or []
    if not lines:
        return "Preview empty — open the app to add this purchase."
    li = lines[0]
    warnings = content.get("warnings") or []
    wtxt = ""
    if warnings:
        wtxt = "\n⚠️ " + "; ".join(str(w) for w in warnings[:3]) + "\n"
    return (
        "*Preview Harisree entry*\n"
        f"Date: {content.get('entry_date')}\n"
        f"Item: {li.get('item_name')}\n"
        f"Qty: {li.get('qty')} {li.get('unit')}\n"
        f"Buy: ₹{float(li.get('buy_price') or 0):,.2f}\n"
        f"Landing: ₹{float(li.get('landing_cost') or 0):,.2f}\n"
        f"{wtxt}\n"
        "Reply *YES* to save or *NO* to cancel."
    )


def _format_update_preview(entry: Entry, patch: dict[str, Any]) -> str:
    li = sorted(entry.lines, key=lambda x: x.id)[0] if entry.lines else None
    if not li:
        return "Could not load entry line."
    lines = [
        f"Item: {li.item_name}",
        f"Current buy ₹{float(li.buy_price):,.2f} | land ₹{float(li.landing_cost):,.2f}",
    ]
    if patch.get("buy_price") is not None:
        lines.append(f"→ New buy: ₹{float(patch['buy_price']):,.2f}")
    if patch.get("landing_cost") is not None:
        lines.append(f"→ New landing: ₹{float(patch['landing_cost']):,.2f}")
    if patch.get("selling_price") is not None:
        lines.append(f"→ New selling: ₹{float(patch['selling_price']):,.2f}")
    return "*Update entry (preview)*\n" + "\n".join(lines) + "\n\nReply *YES* to apply or *NO* to cancel."


async def _run_query(
    db: AsyncSession,
    business_id: uuid.UUID,
    data: dict[str, Any],
) -> str:
    qk = (data.get("query_kind") or data.get("kind") or "").strip().lower()
    dr = data.get("date_range") or "month"
    if isinstance(dr, str):
        dr = dr.lower().strip()
    item = (data.get("item") or data.get("item_name") or "").strip()

    if qk == "greeting":
        return (
            "Harisree Purchase Assistant — send *TODAY* or *OVERVIEW* for reports, "
            "or a purchase draft:\n"
            "item: …\nqty: …\nunit: kg|box|piece\nbuy: …\nland: …\n\n"
            "After we send a preview, reply *YES* to save (nothing is stored until then)."
        )

    if qk == "help_menu":
        return (
            "*What I can do*\n"
            "• Reports: *TODAY*, *OVERVIEW*, *BEST SUPPLIER*, *profit <item> week|month|today*\n"
            "• Add purchase: send a multiline draft with item, qty, unit (kg|box|piece), buy, land\n"
            "• Masters: *add supplier Name*, *add broker Name*, *add item Name*\n"
            "• Nothing is saved until you reply *YES* to a preview.\n"
            "Say *help* anytime."
        )

    if qk in ("today_summary", "today"):
        return await format_today_summary(db, business_id)
    if qk in ("month_summary", "month", "overview", "mtd"):
        return await format_month_summary(db, business_id)
    if qk in ("best_supplier_mtd", "best_supplier", "top_supplier"):
        return await format_best_supplier_mtd(db, business_id)
    if qk in ("best_supplier_for_item", "best_for_item"):
        return await format_best_supplier_for_item_mtd(db, business_id, item or "x")
    if qk == "item_profit" and item:
        frm, to = date_range_to_bounds(str(dr) if dr else "month")
        return await format_item_profit(db, business_id, item, frm, to)
    if qk in ("broker_commission", "broker_impact"):
        frm, to = date_range_to_bounds(str(dr) if dr else "month")
        return await format_broker_commission_mtd(db, business_id, frm, to)
    if qk in ("supplier_compare", "compare_suppliers") and item:
        frm, to = date_range_to_bounds(str(dr) if dr else "month")
        return await format_supplier_compare_top2(db, business_id, item, frm, to)
    if qk == "price_check":
        price = float(data.get("price") or 0)
        it = item or "item"
        return (
            f"Noted: {it} @ ₹{price:,.2f}. Open the app Price Intelligence for full range & trend.\n"
            "To record a purchase, send a multiline draft (item/qty/unit/buy/land)."
        )
    if qk in ("purchase_overview", "range_summary") and dr:
        frm, to = date_range_to_bounds(str(dr))
        # reuse month-style totals for arbitrary range
        bf = (
            Entry.business_id == business_id,
            Entry.entry_date >= frm,
            Entry.entry_date <= to,
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
            f"📊 *Purchases* ({frm} → {to})\n"
            f"🛒 Purchase: ₹{p:,.0f}\n"
            f"📈 Profit: ₹{pr:,.0f} ({margin:.1f}%)"
        )

    # generic query from LLM — try item profit if item present
    if item and dr:
        frm, to = date_range_to_bounds(str(dr))
        return await format_item_profit(db, business_id, item, frm, to)

    return (
        "Try: *OVERVIEW*, *TODAY*, *BEST SUPPLIER*, *profit rice week*, or a purchase draft:\n"
        "item: …\nqty: …\nunit: kg|box|piece\nbuy: …\nland: …"
    )


async def handle_transactional_message(
    *,
    settings: Settings,
    db: AsyncSession,
    phone_digits: str,
    text: str,
    user: User,
    business_id: uuid.UUID,
) -> dict[str, Any]:
    to = phone_digits
    t = (text or "").strip()
    low = t.lower()

    async def _wa(body: str, *, scene: str | None = None) -> None:
        """Send outbound text; optionally polish with grounded LLM when enabled."""
        out = body
        if scene:
            try:
                polished = await maybe_polish_whatsapp_reply(
                    scene=scene,  # type: ignore[arg-type]
                    user_text=t,
                    server_message=body,
                    settings=settings,
                    db=db,
                )
                if polished:
                    out = polished
            except Exception as e:  # noqa: BLE001
                logger.warning("WhatsApp reply polish skipped: %s", e)
        await send_guarded_whatsapp(settings, db, to_e164=to, body=out)

    state = await get_state(settings, to) or {"phase": "idle"}

    # --- pending confirmation (new engine state) ---
    if state.get("phase") == "pending_confirm":
        if _is_no(t):
            await set_state(settings, to, {"phase": "idle"})
            await _wa("Cancelled. Send a new message when ready.", scene="action")
            return {"ok": True, "handled": True, "cancelled": True}

        kind = state.get("kind") or "legacy_entry"

        if kind == "create_entry":
            if state.get("duplicate_pending") and _is_yes(t) and not _wants_force_duplicate(t):
                await send_guarded_whatsapp(
                    settings,
                    db,
                    to_e164=to,
                    body="This may duplicate an existing line. Reply *YES FORCE* to save anyway, or *NO* to cancel.",
                )
                return {"ok": True, "handled": True, "prompt": True}

            if not (_is_yes(t) or (state.get("duplicate_pending") and _wants_force_duplicate(t))):
                await send_guarded_whatsapp(
                    settings,
                    db,
                    to_e164=to,
                    body="Reply *YES* to save, *NO* to cancel."
                    + (
                        "\nIf this might duplicate an existing line, reply *YES FORCE* to save anyway."
                        if state.get("duplicate_pending")
                        else ""
                    ),
                )
                return {"ok": True, "handled": True, "prompt": True}

            raw = state.get("serialized_entry")
            if not raw:
                await set_state(settings, to, {"phase": "idle"})
                await send_guarded_whatsapp(settings, db, to_e164=to, body="Session expired — send the draft again.")
                return {"ok": True, "handled": True, "error": "stale"}

            body = EntryCreateRequest.model_validate(raw)
            token = state.get("preview_token")
            body = body.model_copy(
                update={
                    "preview_token": token,
                    "confirm": True,
                    "force_duplicate": bool(state.get("duplicate_pending") and _wants_force_duplicate(t)),
                }
            )
            try:
                await commit_create_entry_confirmed(
                    db, business_id=business_id, user_id=user.id, body=body, source="whatsapp"
                )
            except HTTPException as e:
                if int(e.status_code) == int(status.HTTP_409_CONFLICT):
                    detail = e.detail
                    ids: list[str] = []
                    if isinstance(detail, dict):
                        ids = [str(x) for x in (detail.get("matching_entry_ids") or [])]
                    await set_state(
                        settings,
                        to,
                        {
                            **state,
                            "duplicate_pending": True,
                            "phase": "pending_confirm",
                            "kind": "create_entry",
                        },
                    )
                    await send_guarded_whatsapp(
                        settings,
                        db,
                        to_e164=to,
                        body=(
                            "⚠️ Possible duplicate in Harisree.\n"
                            + (f"Matches: {', '.join(ids[:3])}\n" if ids else "")
                            + "Reply *YES FORCE* to save anyway, or *NO* to cancel."
                        ),
                    )
                    return {"ok": True, "handled": True, "duplicate": True}
                await send_guarded_whatsapp(
                    settings,
                    db,
                    to_e164=to,
                    body="Could not save. Open the app to fix details, or try again.",
                )
                return {"ok": False, "handled": True, "error": str(e.detail)}
            await set_state(settings, to, {"phase": "idle"})
            await _wa("✅ Saved in Harisree.", scene="action")
            return {"ok": True, "handled": True, "saved": True}

        if kind == "update_entry":
            if not _is_yes(t):
                await send_guarded_whatsapp(
                    settings, db, to_e164=to, body="Reply *YES* to apply changes or *NO* to cancel."
                )
                return {"ok": True, "handled": True, "prompt": True}
            eid = state.get("entry_id")
            patch = state.get("patch") or {}
            if not eid:
                await set_state(settings, to, {"phase": "idle"})
                return {"ok": True, "handled": True, "error": "stale"}
            sup_id = None
            br_id = None
            if patch.get("supplier_id"):
                sup_id = uuid.UUID(str(patch["supplier_id"]))
            if patch.get("broker_id"):
                br_id = uuid.UUID(str(patch["broker_id"]))
            ent = await patch_first_line_prices(
                db,
                business_id,
                uuid.UUID(str(eid)),
                buy_price=patch.get("buy_price"),
                landing_cost=patch.get("landing_cost"),
                selling_price=patch.get("selling_price"),
                supplier_id=sup_id,
                broker_id=br_id,
                entry_date=patch.get("entry_date"),
            )
            await set_state(settings, to, {"phase": "idle"})
            if ent:
                await _wa("✅ Entry updated.", scene="action")
            else:
                await send_guarded_whatsapp(settings, db, to_e164=to, body="Could not update — open the app.")
            return {"ok": True, "handled": True, "updated": bool(ent)}

        if kind in ("create_supplier", "create_broker", "create_item"):
            if not _is_yes(t):
                await send_guarded_whatsapp(
                    settings, db, to_e164=to, body="Reply *YES* to create or *NO* to cancel."
                )
                return {"ok": True, "handled": True, "prompt": True}
            pending = state.get("pending_master") or {}
            try:
                if kind == "create_supplier":
                    status_s, _ = await insert_supplier_if_new(
                        db,
                        business_id,
                        str(pending.get("name")),
                        phone=str(pending.get("phone")) if pending.get("phone") else None,
                    )
                    msg = "Supplier ready (already existed)." if status_s == "exists" else "✅ Supplier created."
                elif kind == "create_broker":
                    status_s, _ = await insert_broker_if_new(
                        db,
                        business_id,
                        str(pending.get("name")),
                        commission_flat=pending.get("commission_flat"),
                    )
                    msg = "Broker ready (already existed)." if status_s == "exists" else "✅ Broker created."
                else:
                    status_s, _ = await insert_catalog_item_if_new(
                        db,
                        business_id,
                        str(pending.get("category_name")),
                        str(pending.get("item_name")),
                    )
                    msg = "Item already in catalog." if status_s == "exists" else "✅ Catalog item created."
            except Exception as e:  # noqa: BLE001
                logger.warning("master create failed: %s", e)
                msg = "Could not save — open the app to add this."
            await set_state(settings, to, {"phase": "idle"})
            await _wa(msg, scene="action")
            return {"ok": True, "handled": True, "master": True}

        # legacy pending_confirm (draft only)
        if isinstance(state.get("draft"), dict) and "lines" in state["draft"]:
            if not _is_yes(t):
                await send_guarded_whatsapp(
                    settings, db, to_e164=to, body="Reply *YES* to save or *NO* to cancel."
                )
                return {"ok": True, "handled": True, "prompt": True}
            raw_body = _legacy_draft_to_request(state["draft"])
            try:
                content, prepared = await prepare_create_entry_preview(
                    db, business_id=business_id, user_id=user.id, body=raw_body
                )
            except HTTPException as e:
                await send_guarded_whatsapp(
                    settings,
                    db,
                    to_e164=to,
                    body=str(e.detail) if isinstance(e.detail, str) else "Invalid entry — check the app.",
                )
                return {"ok": True, "handled": True, "error": "preview"}
            body = prepared.model_copy(
                update={"preview_token": content.get("preview_token"), "confirm": True}
            )
            try:
                await commit_create_entry_confirmed(
                    db, business_id=business_id, user_id=user.id, body=body, source="whatsapp"
                )
            except HTTPException as e:
                if int(e.status_code) == int(status.HTTP_409_CONFLICT):
                    await set_state(
                        settings,
                        to,
                        {
                            "phase": "pending_confirm",
                            "kind": "create_entry",
                            "serialized_entry": prepared.model_dump(mode="json"),
                            "preview_token": content.get("preview_token"),
                            "duplicate_pending": True,
                        },
                    )
                    await send_guarded_whatsapp(
                        settings,
                        db,
                        to_e164=to,
                        body="⚠️ Possible duplicate. Reply *YES FORCE* to save anyway, or *NO* to cancel.",
                    )
                    return {"ok": True, "handled": True, "duplicate": True}
                await send_guarded_whatsapp(settings, db, to_e164=to, body="Could not save — try the app.")
                return {"ok": False, "handled": True}
            await set_state(settings, to, {"phase": "idle"})
            await _wa("✅ Saved in Harisree.", scene="action")
            return {"ok": True, "handled": True, "saved": True}

    # --- awaiting category for create_item ---
    if state.get("phase") == "awaiting_category":
        cat = t.strip()
        if len(cat) < 2:
            await send_guarded_whatsapp(
                settings, db, to_e164=to, body="Send the category name (e.g. *Grains*)."
            )
            return {"ok": True, "handled": True}
        item_name = state.get("item_name") or ""
        await set_state(
            settings,
            to,
            {
                "phase": "pending_confirm",
                "kind": "create_item",
                "pending_master": {
                    "item_name": item_name,
                    "category_name": cat,
                },
            },
        )
        await _wa(
            (
                f"*Create catalog item*\n"
                f"Item: {item_name}\n"
                f"Category: {cat}\n\n"
                "Reply *YES* to create or *NO* to cancel."
            ),
            scene="preview",
        )
        return {"ok": True, "handled": True, "preview": True}

    # --- resume multi-turn purchase draft (Redis + key:value follow-ups) ---
    pending_data = await get_pending_create_fields(settings, to)
    if pending_data:
        extra_kv = parse_whatsapp_kv_lines(t)
        if extra_kv:
            merged_data = merge_kv_into_create_data(pending_data, extra_kv)
            req_slot, miss_slot = await build_entry_create_request(db, business_id, merged_data)
            if req_slot and not miss_slot:
                await clear_pending_create_fields(settings, to)
                try:
                    content, prepared = await prepare_create_entry_preview(
                        db, business_id=business_id, user_id=user.id, body=req_slot
                    )
                except HTTPException as e:
                    await send_guarded_whatsapp(
                        settings,
                        db,
                        to_e164=to,
                        body=str(e.detail) if isinstance(e.detail, str) else "Could not build preview — use the app.",
                    )
                    return {"ok": True, "handled": True, "error": "preview"}
                preview_msg = _format_entry_preview_whatsapp(content)
                await set_state(
                    settings,
                    to,
                    {
                        "phase": "pending_confirm",
                        "kind": "create_entry",
                        "serialized_entry": prepared.model_dump(mode="json"),
                        "preview_token": content.get("preview_token"),
                        "duplicate_pending": False,
                    },
                )
                await _wa(preview_msg, scene="preview")
                return {"ok": True, "handled": True, "preview": True, "draft_resume": True}
            await set_pending_create_fields(settings, to, merged_data)
            hint_slot = f"Still need: {', '.join(miss_slot)}. Add lines like qty: 10 or buy: 100"
            await _wa(hint_slot, scene="clarify")
            return {"ok": True, "handled": True, "missing": True, "draft": True}

    # --- fresh parse ---
    parsed = await merge_parse_async(user_text=t, settings=settings, db=db)
    intent = str(parsed.get("intent") or "out_of_scope")
    if intent not in ALLOWED_INTENTS:
        intent = "out_of_scope"
    conf = float(parsed.get("confidence") or 0)
    data = parsed.get("data") if isinstance(parsed.get("data"), dict) else {}

    if intent in ("query", "create_supplier", "create_broker", "create_item", "update_entry"):
        await clear_pending_create_fields(settings, to)

    # Multiline draft fallback when LLM/rules missed
    if intent == "out_of_scope":
        legacy_body = parse_multiline_entry_create_request(t)
        if legacy_body is not None:
            try:
                content, prepared = await prepare_create_entry_preview(
                    db, business_id=business_id, user_id=user.id, body=legacy_body
                )
            except HTTPException as e:
                await send_guarded_whatsapp(
                    settings,
                    db,
                    to_e164=to,
                    body=str(e.detail) if isinstance(e.detail, str) else "Invalid entry — use the app.",
                )
                return {"ok": True, "handled": True, "error": "preview"}
            preview_msg = _format_entry_preview_whatsapp(content)
            await set_state(
                settings,
                to,
                {
                    "phase": "pending_confirm",
                    "kind": "create_entry",
                    "serialized_entry": prepared.model_dump(mode="json"),
                    "preview_token": content.get("preview_token"),
                    "duplicate_pending": False,
                },
            )
            await _wa(preview_msg, scene="preview")
            return {"ok": True, "handled": True, "preview": True}

    cq = parsed.get("clarification_question")
    if conf < CONFIDENCE_MIN and intent != "query":
        msg = cq if isinstance(cq, str) and cq.strip() else "Say that in one short purchase sentence, or use the multiline draft."
        await _wa(msg, scene="clarify")
        return {"ok": True, "handled": True, "low_confidence": True}

    if intent == "out_of_scope":
        await _wa(
            (
                "I only help with *purchases*, *suppliers/brokers/items*, and *reports*.\n"
                "Try *OVERVIEW*, *TODAY*, or send a draft:\n"
                "item: …\nqty: …\nunit: kg|box|piece\nbuy: …\nland: …"
            ),
            scene="help",
        )
        return {"ok": True, "handled": True, "out_of_scope": True}

    if intent == "query":
        msg = await _run_query(db, business_id, data)
        await _wa(msg, scene="query")
        return {"ok": True, "handled": True, "query": True}

    if intent == "create_entry":
        req, missing = await build_entry_create_request(db, business_id, data)
        mf = list(parsed.get("missing_fields") or [])
        if mf:
            missing = list(dict.fromkeys([*missing, *mf]))
        if missing or req is None:
            await set_pending_create_fields(settings, to, dict(data))
            q = parsed.get("clarification_question")
            hint = q if isinstance(q, str) and q.strip() else f"Missing: {', '.join(missing)}"
            hint = hint + "\n\nSend more lines (e.g. qty: 10, buy: 100) or one full draft in a single message."
            await _wa(hint, scene="clarify")
            return {"ok": True, "handled": True, "missing": True}
        await clear_pending_create_fields(settings, to)
        try:
            content, prepared = await prepare_create_entry_preview(
                db, business_id=business_id, user_id=user.id, body=req
            )
        except HTTPException as e:
            await send_guarded_whatsapp(
                settings,
                db,
                to_e164=to,
                body=str(e.detail) if isinstance(e.detail, str) else "Could not build preview — use the app.",
            )
            return {"ok": True, "handled": True, "error": "preview"}
        preview_msg = _format_entry_preview_whatsapp(content)
        await set_state(
            settings,
            to,
            {
                "phase": "pending_confirm",
                "kind": "create_entry",
                "serialized_entry": prepared.model_dump(mode="json"),
                "preview_token": content.get("preview_token"),
                "duplicate_pending": False,
            },
        )
        await _wa(preview_msg, scene="preview")
        return {"ok": True, "handled": True, "preview": True}

    if intent == "update_entry":
        scope = (data.get("update_scope") or "last").lower()
        entry: Entry | None = None
        if scope == "last":
            entry = await fetch_last_entry_for_business(db, business_id)
        else:
            eid = data.get("target_entry_id")
            if eid:
                r = await db.execute(
                    select(Entry)
                    .where(Entry.id == uuid.UUID(str(eid)), Entry.business_id == business_id)
                    .options(selectinload(Entry.lines))
                )
                entry = r.scalar_one_or_none()
        if entry is None:
            await send_guarded_whatsapp(
                settings, db, to_e164=to, body="No matching entry found — open the app to edit."
            )
            return {"ok": True, "handled": True}
        patch: dict[str, Any] = {}
        if data.get("patch_buy") is not None:
            try:
                patch["buy_price"] = float(data["patch_buy"])
            except (TypeError, ValueError):
                pass
        if data.get("patch_land") is not None:
            try:
                patch["landing_cost"] = float(data["patch_land"])
            except (TypeError, ValueError):
                pass
        if data.get("patch_sell") is not None:
            try:
                patch["selling_price"] = float(data["patch_sell"])
            except (TypeError, ValueError):
                pass
        if data.get("patch_supplier_name"):
            sid = await find_supplier_id_by_name(db, business_id, str(data["patch_supplier_name"]))
            if sid:
                patch["supplier_id"] = str(sid)
        if data.get("patch_broker_name"):
            bid = await find_broker_id_by_name(db, business_id, str(data["patch_broker_name"]))
            if bid:
                patch["broker_id"] = str(bid)
        ed = data.get("patch_entry_date") or data.get("entry_date")
        if ed:
            try:
                patch["entry_date"] = date.fromisoformat(str(ed)[:10])
            except ValueError:
                pass
        if not patch:
            await send_guarded_whatsapp(
                settings,
                db,
                to_e164=to,
                body="What should change? (e.g. new landing price or say *change last entry landing 1200*)",
            )
            return {"ok": True, "handled": True}
        preview = _format_update_preview(entry, patch)
        await set_state(
            settings,
            to,
            {
                "phase": "pending_confirm",
                "kind": "update_entry",
                "entry_id": str(entry.id),
                "patch": patch,
            },
        )
        await _wa(preview, scene="preview")
        return {"ok": True, "handled": True, "preview": True}

    if intent == "create_supplier":
        name = str(data.get("supplier_name") or "").strip()
        if not name:
            await send_guarded_whatsapp(settings, db, to_e164=to, body="Send: *add supplier Name* (optional phone).")
            return {"ok": True, "handled": True}
        phone = data.get("supplier_phone")
        await set_state(
            settings,
            to,
            {
                "phase": "pending_confirm",
                "kind": "create_supplier",
                "pending_master": {"name": name, "phone": str(phone) if phone else None},
            },
        )
        await _wa(
            "Preview (not saved):\n"
            f"Type: Supplier\nName: {name}\nPhone: {phone or '—'}\n\n"
            "Reply YES to save, NO to cancel.",
            scene="preview",
        )
        return {"ok": True, "handled": True, "preview": True}

    if intent == "create_broker":
        name = str(data.get("broker_name") or "").strip()
        if not name:
            await send_guarded_whatsapp(settings, db, to_e164=to, body="Send: *add broker Name*.")
            return {"ok": True, "handled": True}
        comm = data.get("broker_commission_flat")
        try:
            cflat = float(comm) if comm is not None else None
        except (TypeError, ValueError):
            cflat = None
        await set_state(
            settings,
            to,
            {
                "phase": "pending_confirm",
                "kind": "create_broker",
                "pending_master": {"name": name, "commission_flat": cflat},
            },
        )
        await _wa(
            "Preview (not saved):\n"
            f"Type: Broker\nName: {name}\n"
            f"Commission: {cflat if cflat is not None else '—'}\n\n"
            "Reply YES to save, NO to cancel.",
            scene="preview",
        )
        return {"ok": True, "handled": True, "preview": True}

    if intent == "create_item":
        item_name = str(data.get("item_name") or data.get("item") or "").strip()
        cat = data.get("category_name")
        if not item_name:
            await send_guarded_whatsapp(settings, db, to_e164=to, body="Send: *add item Name* or *add item X in category Y*.")
            return {"ok": True, "handled": True}
        if not cat or not str(cat).strip():
            await set_state(
                settings,
                to,
                {"phase": "awaiting_category", "item_name": item_name},
            )
            await send_guarded_whatsapp(
                settings,
                db,
                to_e164=to,
                body=f"Which category should *{item_name}* belong to? (reply with category name)",
            )
            return {"ok": True, "handled": True}
        await set_state(
            settings,
            to,
            {
                "phase": "pending_confirm",
                "kind": "create_item",
                "pending_master": {"item_name": item_name, "category_name": str(cat).strip()},
            },
        )
        await _wa(
            "Preview (not saved):\n"
            f"Type: Item\nName: {item_name}\nCategory: {cat}\n\n"
            "Reply YES to save, NO to cancel.",
            scene="preview",
        )
        return {"ok": True, "handled": True, "preview": True}

    await _wa(
        "Could not understand. Send *OVERVIEW* or a purchase draft (item/qty/unit/buy/land).",
        scene="help",
    )
    return {"ok": True, "handled": True, "fallback": True}
