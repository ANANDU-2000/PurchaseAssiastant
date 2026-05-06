"""Scanner V2 pipeline: OCR → LLM parse → matching → normalization.

This module is intentionally side-effect free (no DB writes). The only
write-path for scanner corrections is the `/correct` endpoint which upserts
into `catalog_aliases`.
"""

from __future__ import annotations

import json
import time
import uuid
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Any

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.services import decimal_precision as dp
from app.services.llm_failover import resolve_provider_keys
from app.services.platform_credentials import effective_openai_key
from app.services.purchase_scan_service import image_bytes_to_text
from app.services.scanner_v2 import bag_logic, matcher
from app.services.scanner_v2.prompt import SYSTEM_PROMPT
from app.services.scanner_v2.types import (
    BrokerCommission,
    Candidate,
    Charges,
    ItemRow,
    Match,
    ScanMeta,
    ScanResult,
    Totals,
    Warning,
)


def _now_s() -> float:
    return time.time()


def _d(x: Any) -> Decimal | None:
    try:
        if x is None:
            return None
        if isinstance(x, Decimal):
            return x
        if isinstance(x, (int, float)):
            return Decimal(str(x))
        if isinstance(x, str):
            t = x.strip()
            if not t:
                return None
            return Decimal(t)
    except Exception:  # noqa: BLE001
        return None
    return None


def _parse_json_object_maybe(text: str) -> dict[str, Any] | None:
    if not isinstance(text, str) or not text.strip():
        return None
    try:
        obj = json.loads(text)
    except Exception:  # noqa: BLE001
        return None
    return obj if isinstance(obj, dict) else None


async def _openai_parse_scanner_payload(
    *,
    text: str,
    settings: Settings,
    db: AsyncSession,
) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    """Return raw parsed dict matching the scanner prompt schema."""
    key = await effective_openai_key(settings, db)
    if not key:
        return None, {"provider_used": None, "failover": [{"provider": "openai", "skipped": True, "reason": "no_key"}]}

    payload = {
        "model": settings.openai_model_parse,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": (text or "")[:12000]},
        ],
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            json=payload,
        )
        if res.status_code >= 400:
            return None, {
                "provider_used": None,
                "failover": [{"provider": "openai", "ok": False, "error": res.text[:200]}],
            }
        data = res.json()
    try:
        content = data["choices"][0]["message"]["content"]
    except Exception:  # noqa: BLE001
        return None, {"provider_used": None, "failover": [{"provider": "openai", "ok": False, "reason": "bad_response"}]}
    raw = _parse_json_object_maybe(content)
    return raw, {"provider_used": "openai", "failover": [{"provider": "openai", "ok": bool(raw)}]}


async def _match_supplier_broker(
    *,
    db: AsyncSession,
    business_id: uuid.UUID,
    supplier_name: str | None,
    broker_name: str | None,
) -> tuple[Match, Match | None]:
    supplier = await matcher.match_one(db=db, business_id=business_id, raw_text=(supplier_name or ""), type="supplier")
    broker = None
    if broker_name is not None and str(broker_name).strip():
        broker = await matcher.match_one(db=db, business_id=business_id, raw_text=str(broker_name), type="broker")
    return supplier, broker


async def _match_items(
    *,
    db: AsyncSession,
    business_id: uuid.UUID,
    items: list[dict[str, Any]],
) -> list[ItemRow]:
    out: list[ItemRow] = []
    for it in items:
        if not isinstance(it, dict):
            continue
        raw_name = str(it.get("name") or it.get("raw_name") or it.get("item_name") or "").strip()
        if not raw_name:
            continue

        m = await matcher.match_one(db=db, business_id=business_id, raw_text=raw_name, type="item")
        row = ItemRow(
            raw_name=raw_name,
            matched_catalog_item_id=m.matched_id,
            matched_name=m.matched_name,
            confidence=m.confidence,
            match_state=m.match_state,
            candidates=m.candidates,
            unit_type=str(it.get("unit_type") or it.get("unit") or "KG").strip().upper(),
            weight_per_unit_kg=_d(it.get("weight_per_unit_kg") or it.get("weight_per_unit")),
            bags=_d(it.get("bags")),
            total_kg=_d(it.get("total_kg")),
            qty=_d(it.get("qty")),
            purchase_rate=_d(it.get("purchase_rate")),
            selling_rate=_d(it.get("selling_rate")),
            delivered_rate=_d(it.get("delivered_rate")),
            billty_rate=_d(it.get("billty_rate")),
            freight_amount=_d(it.get("freight_amount")),
            discount=_d(it.get("discount") or it.get("discount_percent")),
            tax_percent=_d(it.get("tax_percent")),
            notes=(str(it.get("notes")).strip() if it.get("notes") is not None else None),
        )
        out.append(row)
    return out


def _confidence_from_matches(supplier: Match, broker: Match | None, items: list[ItemRow]) -> float:
    scores: list[float] = []
    if supplier.match_state != "unresolved":
        scores.append(float(supplier.confidence))
    if broker is not None and broker.match_state != "unresolved":
        scores.append(float(broker.confidence))
    for it in items:
        if it.match_state != "unresolved":
            scores.append(float(it.confidence))
    if not scores:
        return 0.0
    return max(0.0, min(1.0, sum(scores) / len(scores)))


def _needs_review(supplier: Match, items: list[ItemRow]) -> bool:
    if supplier.match_state != "auto":
        return True
    for it in items:
        if it.match_state != "auto":
            return True
    return False


def _compute_preview_line_total(it: ItemRow, warnings: list[Warning]) -> Decimal | None:
    """Best-effort preview total. Final total is computed on confirm-save."""
    r = it.purchase_rate
    if r is None or r <= 0:
        return None
    u = it.unit_type
    if u == "KG":
        q = it.qty or it.total_kg
        if q is None or q <= 0:
            return None
        return dp.total(q * r)
    if u == "PCS":
        q = it.qty
        if q is None or q <= 0:
            return None
        return dp.total(q * r)
    if u in ("BOX", "TIN"):
        q = it.qty
        if q is None or q <= 0:
            return None
        return dp.total(q * r)
    if u == "BAG":
        bags = it.bags or it.qty
        wpu = it.weight_per_unit_kg
        if bags is None or bags <= 0:
            return None
        # Heuristic: small rates are typically ₹/kg; large rates are ₹/bag.
        if wpu is not None and wpu > 0 and r < Decimal("500"):
            return dp.total(bags * wpu * r)
        if wpu is not None and wpu > 0 and r >= Decimal("500"):
            return dp.total(bags * r)
        warnings.append(
            Warning(
                code="BAG_RATE_AMBIGUOUS",
                severity="warn",
                target="items[].purchase_rate",
                message="Bag line total could not be computed confidently (missing weight per bag).",
                suggestion="Confirm kg per bag and whether the rate is ₹/kg or ₹/bag.",
            )
        )
        return None
    return None


@dataclass
class _ScanCacheEntry:
    business_id: uuid.UUID
    created_at_s: float
    result: ScanResult


_SCAN_CACHE_TTL_S = 20 * 60.0
_SCAN_CACHE_MAX = 256
_SCAN_CACHE: dict[str, _ScanCacheEntry] = {}


def _put_scan_cache(token: str, entry: _ScanCacheEntry) -> None:
    if len(_SCAN_CACHE) >= _SCAN_CACHE_MAX:
        # Drop oldest (simple O(n) is fine at this size).
        oldest = sorted(_SCAN_CACHE.items(), key=lambda kv: kv[1].created_at_s)[:32]
        for k, _ in oldest:
            _SCAN_CACHE.pop(k, None)
    _SCAN_CACHE[token] = entry


def get_cached_scan_result(*, business_id: uuid.UUID, scan_token: str) -> ScanResult | None:
    e = _SCAN_CACHE.get(scan_token)
    if not e:
        return None
    if e.business_id != business_id:
        return None
    if _now_s() - e.created_at_s > _SCAN_CACHE_TTL_S:
        _SCAN_CACHE.pop(scan_token, None)
        return None
    return e.result


def consume_cached_scan_result(*, business_id: uuid.UUID, scan_token: str) -> ScanResult | None:
    """Atomically fetch and remove the cached scan.

    Prevents accidental double-save on rapid taps: a scan_token can be confirmed once.
    """
    e = _SCAN_CACHE.get(scan_token)
    if not e:
        return None
    if e.business_id != business_id:
        return None
    if _now_s() - e.created_at_s > _SCAN_CACHE_TTL_S:
        _SCAN_CACHE.pop(scan_token, None)
        return None
    _SCAN_CACHE.pop(scan_token, None)
    return e.result


def update_cached_scan_result(*, business_id: uuid.UUID, scan_token: str, scan: ScanResult) -> bool:
    """Replace cached scan result (used for editable review UI)."""
    e = _SCAN_CACHE.get(scan_token)
    if not e:
        return False
    if e.business_id != business_id:
        return False
    if _now_s() - e.created_at_s > _SCAN_CACHE_TTL_S:
        _SCAN_CACHE.pop(scan_token, None)
        return False
    _SCAN_CACHE[scan_token] = _ScanCacheEntry(
        business_id=business_id,
        created_at_s=e.created_at_s,
        result=scan,
    )
    return True


async def scan_purchase_v2(
    *,
    db: AsyncSession,
    business_id: uuid.UUID,
    settings: Settings,
    image_bytes: bytes,
) -> ScanResult:
    """Full scan pipeline returning an editable preview + scan_token."""
    text, _conf = await image_bytes_to_text(settings, image_bytes)
    scan_meta = ScanMeta(image_bytes_in=len(image_bytes or b""), ocr_chars=len(text or ""))

    raw, meta = await _openai_parse_scanner_payload(text=text, settings=settings, db=db)
    scan_meta.provider_used = meta.get("provider_used")
    scan_meta.failover = meta.get("failover") or []

    supplier_name = None
    broker_name = None
    items_raw: list[dict[str, Any]] = []
    charges_raw: dict[str, Any] = {}
    comm_raw: dict[str, Any] | None = None
    payment_days = None

    if isinstance(raw, dict):
        supplier_name = raw.get("supplier_name") or raw.get("supplier") or None
        broker_name = raw.get("broker_name") or raw.get("broker") or None
        items_raw = raw.get("items") if isinstance(raw.get("items"), list) else []
        charges_raw = raw.get("charges") if isinstance(raw.get("charges"), dict) else {}
        comm_raw = raw.get("broker_commission") if isinstance(raw.get("broker_commission"), dict) else None
        try:
            payment_days = int(raw.get("payment_days")) if raw.get("payment_days") is not None else None
        except Exception:  # noqa: BLE001
            payment_days = None

    supplier, broker = await _match_supplier_broker(
        db=db, business_id=business_id, supplier_name=str(supplier_name or ""), broker_name=(str(broker_name) if broker_name is not None else None)
    )
    items = await _match_items(db=db, business_id=business_id, items=items_raw)

    warnings: list[Warning] = []

    # Normalize unit types + bag/kg reconciliation.
    for it in items:
        # Derive unit type from name + explicit unit + catalog hint (when matched).
        cat_hint: dict[str, Any] | None = None
        if it.matched_catalog_item_id is not None:
            # matcher already queried CatalogItem list internally; avoid re-fetch here.
            # For now, rely on name-based logic + explicit unit_type from LLM.
            cat_hint = None
        it.unit_type = bag_logic.detect_unit_type(it.raw_name, explicit_unit=it.unit_type, catalog=cat_hint)
        # Normalize BAG/KG fields.
        for code in bag_logic.normalize_bag_kg(it, catalog=cat_hint):
            warnings.append(
                Warning(
                    code=code,
                    severity="info",
                    target="items[]",
                    message=f"{code}",
                )
            )
        it.line_total = _compute_preview_line_total(it, warnings)

    charges = Charges(
        delivered_rate=_d(charges_raw.get("delivered_rate")),
        billty_rate=_d(charges_raw.get("billty_rate")),
        freight_amount=_d(charges_raw.get("freight_amount")),
        freight_type=(str(charges_raw.get("freight_type")).strip().lower() if charges_raw.get("freight_type") else None),
        discount_percent=_d(charges_raw.get("discount_percent")),
    )

    broker_commission = None
    if comm_raw:
        try:
            broker_commission = BrokerCommission(
                type=str(comm_raw.get("type") or "percent"),
                value=_d(comm_raw.get("value")) or Decimal("0"),
                applies_to=(str(comm_raw.get("applies_to")) if comm_raw.get("applies_to") is not None else None),
            )
        except Exception:  # noqa: BLE001
            broker_commission = None

    totals = Totals(
        total_bags=dp.qty(sum((it.bags or Decimal("0")) for it in items if it.unit_type == "BAG")),
        total_kg=dp.total_weight(
            sum((it.total_kg or Decimal("0")) for it in items if it.unit_type in ("BAG", "KG"))
        ),
        total_amount=dp.total(sum((it.line_total or Decimal("0")) for it in items)),
    )

    token = str(uuid.uuid4())
    result = ScanResult(
        supplier=supplier,
        broker=broker,
        items=items,
        charges=charges,
        broker_commission=broker_commission,
        payment_days=payment_days,
        totals=totals,
        confidence_score=_confidence_from_matches(supplier, broker, items),
        needs_review=_needs_review(supplier, items),
        warnings=warnings,
        scan_token=token,
        scan_meta=scan_meta,
    )
    _put_scan_cache(token, _ScanCacheEntry(business_id=business_id, created_at_s=_now_s(), result=result))
    return result


def scan_result_to_trade_purchase_create(
    *,
    business_id: uuid.UUID,
    scan: ScanResult,
    purchase_date: date,
    invoice_number: str | None = None,
    status: str = "confirmed",
    force_duplicate: bool = False,
) -> dict[str, Any]:
    """Convert confirmed ScanResult into TradePurchaseCreateRequest payload dict.

    The API model (`TradePurchaseCreateRequest`) will validate this dict.
    """
    if scan.supplier.matched_id is None:
        raise ValueError("supplier must be matched before confirm")
    lines: list[dict[str, Any]] = []
    for it in scan.items:
        if it.matched_catalog_item_id is None:
            raise ValueError("all items must be matched before confirm")
        unit = it.unit_type
        if unit == "PCS":
            unit_str = "piece"
        else:
            unit_str = unit.lower()
        if unit == "KG":
            qty = it.qty or it.total_kg
            if qty is None or qty <= 0:
                raise ValueError("kg line missing qty")
            pr = it.purchase_rate or Decimal("0")
            sr = it.selling_rate
            lines.append(
                {
                    "catalog_item_id": str(it.matched_catalog_item_id),
                    "item_name": it.matched_name or it.raw_name,
                    "qty": str(dp.qty(qty)),
                    "unit": unit_str,
                    "purchase_rate": str(dp.rate(pr)),
                    "landing_cost": str(dp.rate(pr)),
                    "selling_rate": str(dp.rate(sr)) if sr is not None else None,
                }
            )
            continue
        if unit == "BAG":
            bags = it.bags or it.qty
            wpu = it.weight_per_unit_kg
            pr = it.purchase_rate or Decimal("0")
            if bags is None or bags <= 0 or wpu is None or wpu <= 0:
                raise ValueError("bag line missing bags or weight_per_unit_kg")
            # Normalize: always send kg_per_unit + landing_cost_per_kg for BAG so math is deterministic.
            # If purchase_rate looks per-bag (large), convert to per-kg snapshot.
            looks_per_bag = pr >= Decimal("500")
            lcpk = (pr / wpu) if looks_per_bag else pr
            per_bag = pr if looks_per_bag else (pr * wpu)
            sr = it.selling_rate
            if sr is not None:
                sr_looks_per_bag = sr >= Decimal("500")
                sr_per_bag = sr if sr_looks_per_bag else (sr * wpu)
            else:
                sr_per_bag = None
            lines.append(
                {
                    "catalog_item_id": str(it.matched_catalog_item_id),
                    "item_name": it.matched_name or it.raw_name,
                    "qty": str(dp.qty(bags)),
                    "unit": unit_str,
                    "weight_per_unit": str(dp.weight(wpu)),
                    "kg_per_unit": str(dp.weight(wpu)),
                    "landing_cost_per_kg": str(dp.rate(lcpk)),
                    "purchase_rate": str(dp.rate(per_bag)),
                    "landing_cost": str(dp.rate(per_bag)),
                    "selling_rate": (str(dp.rate(sr_per_bag)) if sr_per_bag is not None else None),
                    "selling_cost": (str(dp.rate(sr_per_bag)) if sr_per_bag is not None else None),
                }
            )
            continue
        # BOX/TIN: count-only.
        qty = it.qty
        pr = it.purchase_rate or Decimal("0")
        sr = it.selling_rate
        if qty is None or qty <= 0:
            raise ValueError("count line missing qty")
        lines.append(
            {
                "catalog_item_id": str(it.matched_catalog_item_id),
                "item_name": it.matched_name or it.raw_name,
                "qty": str(dp.qty(qty)),
                "unit": unit_str,
                "purchase_rate": str(dp.rate(pr)),
                "landing_cost": str(dp.rate(pr)),
                "selling_rate": str(dp.rate(sr)) if sr is not None else None,
            }
        )
    return {
        "purchase_date": purchase_date.isoformat(),
        "invoice_number": invoice_number,
        "supplier_id": str(scan.supplier.matched_id),
        "broker_id": str(scan.broker.matched_id) if (scan.broker and scan.broker.matched_id) else None,
        "force_duplicate": force_duplicate,
        "status": status,
        "payment_days": scan.payment_days,
        "discount": str(dp.percent(scan.charges.discount_percent)) if scan.charges.discount_percent is not None else None,
        "delivered_rate": str(dp.money(scan.charges.delivered_rate)) if scan.charges.delivered_rate is not None else None,
        "billty_rate": str(dp.money(scan.charges.billty_rate)) if scan.charges.billty_rate is not None else None,
        "freight_amount": str(dp.money(scan.charges.freight_amount)) if scan.charges.freight_amount is not None else None,
        "freight_type": scan.charges.freight_type,
        "lines": lines,
    }

