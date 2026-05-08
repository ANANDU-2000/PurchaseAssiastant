"""Scanner v3: realtime, offline-tolerant scan jobs (start → status → confirm).

Design goals:
- FAST + RELIABLE: never block UI on a single long request
- REALTIME: status polling shows true backend stage (not a fake timer)
- PARTIAL SUCCESS: return best-effort ScanResult even on OCR/parse failures
- RETRY WITHOUT REUPLOAD: reuse cached image bytes + OCR text when available

Implementation note:
- This is an in-memory job cache (like scanner_v2 scan_token cache).
- Production deployments with multiple workers should back this with Redis/Supabase.
"""

from __future__ import annotations

import asyncio
import time
import uuid
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.database import async_session_factory
from app.services.purchase_scan_service import image_bytes_to_text
from app.services.scanner_v2.pipeline import (
    _confidence_from_matches,
    _compute_preview_line_total,
    _d,
    _match_items,
    _match_supplier_broker,
    _openai_parse_scanner_image_payload,
    _openai_parse_scanner_payload,
    compute_bill_fingerprint,
    llm_payload_is_not_a_bill,
    normalize_llm_scan_dict,
    parse_bill_date_maybe,
)
from app.services.scanner_v2 import bag_logic
from app.services.scanner_v2.types import BrokerCommission, Charges, Match, ScanMeta, ScanResult, Totals, Warning


_SCAN_CACHE_TTL_S = 60 * 25


def _now_s() -> float:
    return time.time()


@dataclass
class _Job:
    business_id: uuid.UUID
    user_id: uuid.UUID | None
    created_at_s: float
    stage: str
    stage_progress: float
    stage_log: list[dict[str, Any]]
    image_bytes: bytes
    ocr_text: str
    result: ScanResult | None
    done: bool
    err: str | None


_JOBS: dict[str, _Job] = {}


def _push_stage(job: _Job, stage: str, progress: float | None = None, **extra: Any) -> None:
    job.stage = stage
    if progress is not None:
        job.stage_progress = float(progress)
    job.stage_log.append({"t": _now_s(), "stage": stage, "progress": job.stage_progress, **extra})
    if job.result is not None:
        job.result.scan_meta.stage = stage
        job.result.scan_meta.stage_progress = job.stage_progress
        job.result.scan_meta.stage_log = list(job.stage_log)


def _empty_result(*, stage: str, image_bytes_in: int) -> ScanResult:
    supplier = Match(
        raw_text="",
        matched_id=None,
        matched_name=None,
        confidence=0.0,
        match_state="unresolved",
        candidates=[],
    )
    meta = ScanMeta(image_bytes_in=image_bytes_in, ocr_chars=0, stage=stage, stage_progress=0.0)
    return ScanResult(
        supplier=supplier,
        broker=None,
        items=[],
        charges=Charges(),
        broker_commission=None,
        payment_days=None,
        totals=Totals(),
        confidence_score=0.0,
        needs_review=True,
        warnings=[],
        scan_token="",
        scan_meta=meta,
    )


async def _run_job(*, token: str, settings: Settings) -> None:
    job = _JOBS.get(token)
    if job is None:
        return
    try:
        async with async_session_factory() as db:
            await _run_job_with_db(token=token, settings=settings, db=db)
    except Exception as e:  # noqa: BLE001
        job = _JOBS.get(token)
        if job is None:
            return
        job.err = f"{type(e).__name__}"
        job.done = True
        if job.result is None:
            job.result = _empty_result(stage="error", image_bytes_in=len(job.image_bytes or b""))
        job.result.scan_meta.error_stage = job.result.scan_meta.error_stage or "scan"
        job.result.scan_meta.error_code = job.result.scan_meta.error_code or "SCAN_FAILED"
        job.result.scan_meta.error_message = job.result.scan_meta.error_message or job.err
        _push_stage(job, "error", 1.0, error=job.err)


def _fallback_parse_text(text: str) -> dict[str, Any]:
    """Deterministic fallback for common trader handwritten patterns.

    Handles patterns like:
    - Supplier: Surag
    - Broker: kkk
    - Sugar 50kg
    - 100 bags
    - 57 58   (purchase/selling)
    - delivered 56 / del 56
    - payment 7 / 7 days
    """
    import re

    t = (text or "").strip()
    lines = [ln.strip() for ln in t.splitlines() if ln.strip()]

    supplier = None
    broker = None
    payment_days = None
    delivered = None

    # Explicit labels (handwritten notes often use "Supplier:" / "Broker:").
    for ln in lines[:12]:
        m = re.match(r"(?i)^\s*supplier\s*[:=]\s*(.+)$", ln)
        if m:
            supplier = m.group(1).strip() or supplier
            continue
        m = re.match(r"(?i)^\s*broker\s*[:=]\s*(.+)$", ln)
        if m:
            broker = m.group(1).strip() or broker
            continue

    # Supplier / broker hints: first 1–3 non-numeric-ish lines.
    for ln in lines[:6]:
        low = ln.lower()
        if supplier is None and ("supplier" in low or "sup" in low):
            supplier = re.sub(r"(?i)\b(supplier|sup)\b\W*", "", ln).strip() or None
            continue
        if broker is None and ("broker" in low or "brk" in low):
            broker = re.sub(r"(?i)\b(broker|brk)\b\W*", "", ln).strip() or None
            continue
    # If still missing, take first line as supplier when it contains letters.
    if supplier is None:
        for ln in lines[:4]:
            if re.search(r"[A-Za-z\u0D00-\u0D7F]", ln) and not re.search(r"\d", ln):
                supplier = ln
                break
    # Broker: look for a short token line.
    if broker is None:
        for ln in lines[:8]:
            if re.search(r"(?i)\bbroker\b", ln):
                continue
            if supplier is not None and ln.strip().lower() == str(supplier).strip().lower():
                continue
            if 2 <= len(ln) <= 16 and re.search(r"[A-Za-z]", ln) and not re.search(r"\d", ln):
                broker = ln
                break

    m_del = re.search(r"(?i)\b(delivered|deliv|del)\D{0,10}(\d+(?:\.\d+)?)", t)
    if m_del:
        delivered = float(m_del.group(2))

    m_pd = re.search(r"(?i)\b(?:payment|pay)\s*days?\s*[:=]?\s*(\d{1,3})\b", t)
    if m_pd:
        payment_days = int(m_pd.group(1))
    else:
        m_pd = re.search(r"(?i)\b(\d{1,3})\s*(?:days?|pd)\b", t)
        if m_pd:
            payment_days = int(m_pd.group(1))
        else:
            m_pd2 = re.search(r"(?i)\bpayment\D{0,12}(\d{1,3})\b", t)
            if m_pd2:
                payment_days = int(m_pd2.group(1))

    # Item detection: try to find a line with "sugar" or something with KG token.
    item_name = None
    weight_per_unit = None
    for ln in lines:
        m = re.search(r"(?i)\b([A-Za-z][A-Za-z0-9 \-]+?)\s*(\d{1,3})\s*kg\b", ln)
        if m:
            item_name = (m.group(1) or "").strip()
            weight_per_unit = float(m.group(2))
            break
        if "sugar" in ln.lower():
            item_name = ln.strip()
    if item_name is None:
        # last resort: pick first line with letters+digits
        for ln in lines:
            if re.search(r"[A-Za-z]", ln) and re.search(r"\d", ln):
                item_name = ln
                break

    bags = None
    m_bags = re.search(r"(?i)\b(\d+(?:\.\d+)?)\s*(bags?|bag)\b", t)
    if m_bags:
        bags = float(m_bags.group(1))

    pr = None
    sr = None
    m_pl = re.search(r"(?i)\bpurchase\s*rate\D{0,12}(\d{2,4})\b", t)
    m_sl = re.search(r"(?i)\bsell(?:ing)?\s*rate\D{0,12}(\d{2,4})\b", t)
    if m_pl:
        pr = float(m_pl.group(1))
    if m_sl:
        sr = float(m_sl.group(1))
    m_ps = re.search(r"(?i)\bP\s*(\d{2,4})\s+S\s*(\d{2,4})\b", t)
    if m_ps:
        if pr is None:
            pr = float(m_ps.group(1))
        if sr is None:
            sr = float(m_ps.group(2))
    # Shorthand: "57 58" (two adjacent ints) → purchase/selling
    if pr is None or sr is None:
        m_rates = re.search(r"(?<!\d)(\d{2,4})(?:\s+|[/\-])(\d{2,4})(?!\d)", t)
        if m_rates:
            if pr is None:
                pr = float(m_rates.group(1))
            if sr is None:
                sr = float(m_rates.group(2))

    return {
        "supplier_name": supplier,
        "broker_name": broker,
        "items": [
            {
                "name": (item_name or "").strip() or "ITEM",
                "unit_type": "BAG" if (weight_per_unit or 0) > 0 or "kg" in (item_name or "").lower() else "KG",
                "weight_per_unit_kg": weight_per_unit,
                "bags": bags,
                "qty": bags,
                "purchase_rate": pr,
                "selling_rate": sr,
            }
        ]
        if item_name
        else [],
        "charges": {"delivered_rate": delivered, "billty_rate": None, "freight_amount": None, "freight_type": None, "discount_percent": None},
        "broker_commission": None,
        "payment_days": payment_days,
    }


async def _run_job_with_db(*, token: str, settings: Settings, db: AsyncSession) -> None:
    job = _JOBS.get(token)
    if job is None:
        return

    # Stage 1: direct image analysis first, then OCR fallback.
    _push_stage(job, "paper_detected", 0.08)
    _push_stage(job, "parsing_items", 0.22, note="openai_image_direct")
    direct_raw, direct_meta = await _openai_parse_scanner_image_payload(
        image_bytes=job.image_bytes,
        settings=settings,
        db=db,
    )

    if direct_raw is None:
        _push_stage(job, "extracting_text", 0.30, note="openai_vision_text_fallback")
        text, _conf = await image_bytes_to_text(settings, job.image_bytes)
        job.ocr_text = text or ""
    else:
        job.ocr_text = ""

    # Prepare base result (always return something)
    base = _empty_result(stage="extracting_text", image_bytes_in=len(job.image_bytes or b""))
    base.scan_token = token
    base.scan_meta.ocr_chars = len(job.ocr_text or "")
    base.scan_meta.stage_log = list(job.stage_log)
    job.result = base

    if isinstance(direct_raw, dict) and llm_payload_is_not_a_bill(direct_raw):
        base.scan_meta.failover.extend(list(direct_meta.get("failover") or []))
        base.scan_meta.provider_used = direct_meta.get("provider_used")
        base.scan_meta.model_used = direct_meta.get("model_used")
        base.scan_meta.extraction_duration_ms = direct_meta.get("extraction_duration_ms")
        base.scan_meta.error_stage = "scan"
        base.scan_meta.error_code = "NOT_A_BILL"
        base.scan_meta.error_message = "not_a_bill"
        base.scan_meta.parse_warnings.append("not_a_bill")
        base.warnings.append(
            Warning(
                code="NOT_A_BILL",
                severity="blocker",
                target="scan",
                message="This does not look like a purchase bill. Use a bill or broker purchase note photo.",
                suggestion="Retake a clear photo of the wholesale purchase bill or handwritten purchase note.",
            )
        )
        _push_stage(job, "ready", 1.0, note="not_a_bill")
        job.done = True
        from app.services.purchase_scan_trace import record_purchase_scan_trace

        await record_purchase_scan_trace(
            db,
            business_id=job.business_id,
            user_id=job.user_id,
            scan_token=token,
            raw_response=direct_raw,
            normalized=base,
            stage="error",
        )
        return

    if direct_raw is None and not (job.ocr_text or "").strip():
        base.scan_meta.error_stage = "ocr"
        base.scan_meta.error_code = "OCR_EMPTY"
        base.scan_meta.error_message = "no_text"
        _push_stage(job, "ready", 1.0, note="ocr_empty")
        job.done = True
        return

    # Stage 2: parse (LLM) with deterministic fallback
    _push_stage(job, "parsing_items", 0.45)
    if direct_raw is not None:
        raw, meta = direct_raw, direct_meta
        base.scan_meta.parse_warnings.append("openai_image_direct")
    else:
        raw, meta = await _openai_parse_scanner_payload(text=job.ocr_text, settings=settings, db=db)
        base.scan_meta.failover.extend(direct_meta.get("failover") or [])
    base.scan_meta.provider_used = meta.get("provider_used")
    base.scan_meta.failover.extend(meta.get("failover") or [])

    fb = _fallback_parse_text(job.ocr_text)
    if raw is None:
        raw = fb
        base.scan_meta.parse_warnings.append("fallback_parse_used")
    elif isinstance(raw, dict):
        if not raw.get("items") and fb.get("items"):
            raw["items"] = fb["items"]
            base.scan_meta.parse_warnings.append("fallback_items_merged")
        if not str(raw.get("supplier_name") or "").strip() and str(fb.get("supplier_name") or "").strip():
            raw["supplier_name"] = fb.get("supplier_name")
        if not str(raw.get("broker_name") or "").strip() and fb.get("broker_name"):
            raw["broker_name"] = fb.get("broker_name")
        if raw.get("payment_days") is None and fb.get("payment_days") is not None:
            raw["payment_days"] = fb["payment_days"]
        ch = raw.get("charges")
        if not isinstance(ch, dict):
            ch = {}
            raw["charges"] = ch
        fch = fb.get("charges") if isinstance(fb.get("charges"), dict) else {}
        for k in ("delivered_rate", "billty_rate", "freight_amount", "freight_type", "discount_percent"):
            if ch.get(k) in (None, "") and fch.get(k) not in (None, ""):
                ch[k] = fch[k]

    if isinstance(raw, dict) and llm_payload_is_not_a_bill(raw):
        base.scan_meta.provider_used = meta.get("provider_used")
        base.scan_meta.error_stage = "scan"
        base.scan_meta.error_code = "NOT_A_BILL"
        base.scan_meta.error_message = "not_a_bill"
        base.scan_meta.parse_warnings.append("not_a_bill")
        base.warnings.clear()
        base.warnings.append(
            Warning(
                code="NOT_A_BILL",
                severity="blocker",
                target="scan",
                message="This does not look like a purchase bill. Use a bill or broker purchase note photo.",
                suggestion="Retake a clear photo of the wholesale purchase bill or handwritten purchase note.",
            )
        )
        _push_stage(job, "ready", 1.0, note="not_a_bill_text")
        job.done = True
        from app.services.purchase_scan_trace import record_purchase_scan_trace

        await record_purchase_scan_trace(
            db,
            business_id=job.business_id,
            user_id=job.user_id,
            scan_token=token,
            raw_response=raw,
            normalized=base,
            stage="error",
        )
        return

    if isinstance(raw, dict):
        raw = normalize_llm_scan_dict(raw)

    if not isinstance(raw, dict) or not raw.get("items"):
        base.scan_meta.error_stage = base.scan_meta.error_stage or "parse"
        base.scan_meta.error_code = base.scan_meta.error_code or "PARSE_EMPTY"
        base.scan_meta.error_message = base.scan_meta.error_message or "no_structured_parse"

    # Stage 3: matching (supplier/broker/items)
    _push_stage(job, "matching", 0.70)
    invoice_number_out: str | None = None
    bill_date_out = None
    bill_fingerprint_out: str | None = None
    bill_notes_out: str | None = None
    scanned_total_amount = None
    comm_raw_v3: dict[str, Any] | None = None

    supplier_name = raw.get("supplier_name") if isinstance(raw, dict) else None
    broker_name = raw.get("broker_name") if isinstance(raw, dict) else None
    items_raw = raw.get("items") if isinstance(raw, dict) and isinstance(raw.get("items"), list) else []
    charges_raw = raw.get("charges") if isinstance(raw, dict) and isinstance(raw.get("charges"), dict) else {}
    payment_days = raw.get("payment_days") if isinstance(raw, dict) else None

    if isinstance(raw, dict):
        inv = raw.get("invoice_no") or raw.get("invoice_number")
        invoice_number_out = str(inv).strip() if inv not in (None, "") else None
        bill_date_out = parse_bill_date_maybe(raw.get("bill_date"))
        bn = raw.get("notes")
        bill_notes_out = str(bn).strip() if bn not in (None, "") else None
        scanned_total_amount = _d(raw.get("total_amount"))
        fp_src = raw.get("bill_fingerprint")
        bf = str(fp_src).strip() if fp_src not in (None, "") else ""
        if not bf:
            bd_src = raw.get("bill_date")
            bd_for_fp = str(bd_src).strip() if bd_src not in (None, "") else None
            bf = compute_bill_fingerprint(
                invoice_number_out,
                bd_for_fp,
                str(supplier_name or "").strip() or None,
            )
        bill_fingerprint_out = bf if bf else None
        comm_raw_v3 = raw.get("broker_commission") if isinstance(raw.get("broker_commission"), dict) else None

    supplier, broker = await _match_supplier_broker(
        db=db,
        business_id=job.business_id,
        supplier_name=str(supplier_name or ""),
        broker_name=(str(broker_name) if broker_name is not None else None),
    )
    items = await _match_items(db=db, business_id=job.business_id, items=items_raw)

    warnings: list[Warning] = []
    for it in items:
        it.unit_type = bag_logic.detect_unit_type(it.raw_name, explicit_unit=it.unit_type, catalog=None)
        for code in bag_logic.normalize_bag_kg(it, catalog=None):
            warnings.append(Warning(code=code, severity="info", target="items[]", message=f"{code}"))
        it.line_total = _compute_preview_line_total(it, warnings)

    ch = Charges(
        delivered_rate=_d(charges_raw.get("delivered_rate")),
        billty_rate=_d(charges_raw.get("billty_rate")),
        freight_amount=_d(charges_raw.get("freight_amount")),
        freight_type=(str(charges_raw.get("freight_type")) if charges_raw.get("freight_type") else None),
        discount_percent=_d(charges_raw.get("discount_percent")),
    )
    try:
        pd = int(payment_days) if payment_days is not None else None
    except Exception:  # noqa: BLE001
        pd = None

    broker_commission = None
    if comm_raw_v3:
        try:
            broker_commission = BrokerCommission(
                type=str(comm_raw_v3.get("type") or "percent"),
                value=_d(comm_raw_v3.get("value")) or Decimal("0"),
                applies_to=(str(comm_raw_v3.get("applies_to")) if comm_raw_v3.get("applies_to") is not None else None),
            )
        except Exception:  # noqa: BLE001
            broker_commission = None

    # Stage 4: validate + totals
    _push_stage(job, "validating", 0.88)
    totals = Totals()
    for it in items:
        if it.unit_type == "BAG" and it.bags is not None and it.weight_per_unit_kg is not None:
            totals.total_bags += it.bags
            totals.total_kg += (it.bags * it.weight_per_unit_kg)
        if it.line_total is not None:
            totals.total_amount += it.line_total

    if scanned_total_amount is not None and totals.total_amount is not None:
        try:
            if abs(scanned_total_amount - totals.total_amount) > Decimal("0.05"):
                warnings.append(
                    Warning(
                        code="TOTAL_MISMATCH",
                        severity="warn",
                        target="totals",
                        message=(
                            f"Bill total {scanned_total_amount} differs from computed line sum {totals.total_amount}."
                        ),
                    )
                )
        except Exception:  # noqa: BLE001
            pass

    conf = _confidence_from_matches(supplier=supplier, broker=broker, items=items)
    needs_review = True
    if supplier.match_state == "auto" and all(i.match_state == "auto" for i in items) and conf >= 0.92:
        needs_review = False
    if broker is not None and broker.match_state != "auto":
        needs_review = True

    result = ScanResult(
        supplier=supplier,
        broker=broker,
        items=items,
        charges=ch,
        broker_commission=broker_commission,
        payment_days=pd,
        invoice_number=invoice_number_out,
        bill_date=bill_date_out,
        bill_fingerprint=bill_fingerprint_out,
        bill_notes=bill_notes_out,
        scanned_total_amount=scanned_total_amount,
        totals=totals,
        confidence_score=conf,
        needs_review=needs_review,
        warnings=warnings,
        scan_token=token,
        scan_meta=base.scan_meta,
    )
    result.scan_meta.stage_log = list(job.stage_log)
    job.result = result
    from app.services.purchase_scan_trace import record_purchase_scan_trace

    await record_purchase_scan_trace(
        db,
        business_id=job.business_id,
        user_id=job.user_id,
        scan_token=token,
        raw_response=raw if isinstance(raw, dict) else None,
        normalized=result,
        stage="preview",
    )
    _push_stage(job, "ready", 1.0)
    job.done = True


def start_scan(
    *,
    business_id: uuid.UUID,
    image_bytes: bytes,
    settings: Settings,
    user_id: uuid.UUID | None = None,
) -> str:
    token = str(uuid.uuid4())
    job = _Job(
        business_id=business_id,
        user_id=user_id,
        created_at_s=_now_s(),
        stage="preparing_image",
        stage_progress=0.0,
        stage_log=[],
        image_bytes=image_bytes,
        ocr_text="",
        result=None,
        done=False,
        err=None,
    )
    _push_stage(job, "preparing_image", 0.0)
    _JOBS[token] = job
    # Kick off background pipeline.
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        # Unit tests may create/cache v3 scan objects outside a running loop.
        # The API endpoint always has a loop, so production async scans are unaffected.
        pass
    else:
        loop.create_task(_run_job(token=token, settings=settings))
    return token


def get_status(*, business_id: uuid.UUID, scan_token: str) -> ScanResult | None:
    job = _JOBS.get(scan_token)
    if job is None or job.business_id != business_id:
        return None
    if _now_s() - job.created_at_s > _SCAN_CACHE_TTL_S:
        _JOBS.pop(scan_token, None)
        return None
    if job.result is None:
        r = _empty_result(stage=job.stage, image_bytes_in=len(job.image_bytes or b""))
        r.scan_token = scan_token
        r.scan_meta.stage = job.stage
        r.scan_meta.stage_progress = job.stage_progress
        r.scan_meta.stage_log = list(job.stage_log)
        return r
    # Keep meta in sync.
    job.result.scan_meta.stage = job.stage
    job.result.scan_meta.stage_progress = job.stage_progress
    job.result.scan_meta.stage_log = list(job.stage_log)
    return job.result


def consume_result(*, business_id: uuid.UUID, scan_token: str) -> ScanResult | None:
    job = _JOBS.get(scan_token)
    if job is None or job.business_id != business_id:
        return None
    if _now_s() - job.created_at_s > _SCAN_CACHE_TTL_S:
        _JOBS.pop(scan_token, None)
        return None
    if not job.done or job.result is None:
        return None
    _JOBS.pop(scan_token, None)
    return job.result


def update_result(*, business_id: uuid.UUID, scan_token: str, scan: ScanResult) -> bool:
    """Replace a v3 job result after the review UI edits it.

    The v3 mobile flow reuses the v2 confirm endpoint shape. Keeping the
    reviewed result in the v3 cache lets the existing confirm path create the
    purchase from exactly what the user approved.
    """
    job = _JOBS.get(scan_token)
    if job is None or job.business_id != business_id:
        return False
    if _now_s() - job.created_at_s > _SCAN_CACHE_TTL_S:
        _JOBS.pop(scan_token, None)
        return False
    scan.scan_token = scan_token
    scan.scan_meta.stage = "ready"
    scan.scan_meta.stage_progress = 1.0
    job.result = scan
    job.stage = "ready"
    job.stage_progress = 1.0
    job.done = True
    job.err = None
    return True
