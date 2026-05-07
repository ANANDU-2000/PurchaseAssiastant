"""Multipart bill scan → text (Vision when configured) → structured preview (no persistence)."""

from __future__ import annotations

import base64
import json
import logging
import os
from typing import TYPE_CHECKING

import httpx

if TYPE_CHECKING:
    from app.config import Settings

logger = logging.getLogger(__name__)


def _score_text(text: str) -> int:
    """Simple heuristic score: prefer longer, more numeric-heavy OCR."""
    t = (text or "").strip()
    if not t:
        return 0
    digits = sum(1 for ch in t if ch.isdigit())
    letters = sum(1 for ch in t if ch.isalpha())
    lines = t.count("\n") + 1
    return len(t) + digits * 3 + min(40, letters) + min(30, lines * 3)


async def image_bytes_to_text_gemini_free(image_bytes: bytes) -> tuple[str, float]:
    """Uses Gemini Flash (free tier) to extract raw text from a bill image.

    Returns empty string when not configured.
    """
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        return "", 0.0
    if not image_bytes:
        return "", 0.0

    b64 = base64.b64encode(image_bytes).decode("ascii")
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"gemini-2.0-flash:generateContent?key={api_key}"
    )
    payload = {
        "contents": [
            {
                "parts": [
                    {"inline_data": {"mime_type": "image/jpeg", "data": b64}},
                    {
                        "text": (
                            "Extract all text from this purchase bill/handwritten note. "
                            "Preserve exact numbers, names, and spacing. "
                            "Output ONLY the raw extracted text, nothing else."
                        )
                    },
                ]
            }
        ],
        "generationConfig": {"temperature": 0, "maxOutputTokens": 1000},
    }
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            r = await client.post(url, json=payload)
            r.raise_for_status()
            data = r.json()
        text = (
            data.get("candidates", [{}])[0]
            .get("content", {})
            .get("parts", [{}])[0]
            .get("text", "")
        )
        text = (text or "").strip()
        return text, 0.8 if text else 0.0
    except Exception as e:  # noqa: BLE001
        logger.warning("Gemini OCR failed: %s", e)
        return "", 0.0


async def image_bytes_to_text(settings: Settings, image_bytes: bytes) -> tuple[str, float]:
    """Return (extracted_text, confidence_guess).

    Uses Google Vision `DOCUMENT_TEXT_DETECTION` when `enable_ocr` and `ocr_api_key` are set;
    then tries Gemini free OCR (GEMINI_API_KEY) when Vision isn't configured.
    """
    # Preprocess into multiple variants to improve handwriting OCR.
    try:
        from app.services.scanner_v2.preprocess import preprocess_variants

        variants = preprocess_variants(image_bytes)
    except Exception:  # noqa: BLE001
        variants = []
    if not variants:
        variants = [type("V", (), {"name": "orig", "jpeg_bytes": image_bytes})()]  # simple fallback

    best_text = ""
    best_conf = 0.0
    best_score = 0
    # Keep a small pool of strong candidates for later merging. This is critical
    # for handwritten notes where different preprocess variants recover different lines.
    candidates: list[tuple[str, float, int, str]] = []  # (text, conf, score, tag)

    async def _try_vision(jpeg: bytes) -> tuple[str, float]:
        if not getattr(settings, "enable_ocr", False):
            return "", 0.0
        key = getattr(settings, "ocr_api_key", None)
        if not key:
            return "", 0.0
        b64 = base64.b64encode(jpeg).decode("ascii")
        url = f"https://vision.googleapis.com/v1/images:annotate?key={key}"
        payload = {
            "requests": [
                {
                    "image": {"content": b64},
                    "features": [{"type": "DOCUMENT_TEXT_DETECTION", "maxResults": 1}],
                }
            ]
        }
        async with httpx.AsyncClient(timeout=120.0) as client:
            r = await client.post(url, json=payload)
            r.raise_for_status()
            data = r.json()
        resp0 = (data.get("responses") or [{}])[0]
        if resp0.get("error"):
            return "", 0.0
        ann = resp0.get("fullTextAnnotation") or {}
        text = (ann.get("text") or "").strip()
        try:
            conf = float(resp0.get("textAnnotations", [{}])[0].get("confidence", 0.5) or 0.45)
        except Exception:  # noqa: BLE001
            conf = 0.45
        return text, conf if text else 0.0

    for v in variants:
        jpeg = getattr(v, "jpeg_bytes", b"") or b""
        if not jpeg:
            continue
        vname = getattr(v, "name", "orig")
        # 1) Google Vision (when enabled)
        try:
            t, c = await _try_vision(jpeg)
            sc = _score_text(t)
            if t.strip():
                candidates.append((t.strip(), float(c or 0.0), sc, f"vision:{vname}"))
            if sc > best_score:
                best_text, best_conf, best_score = t, c, sc
            if best_score >= 1400:  # early stop when we already got a strong OCR
                break
        except Exception as e:  # noqa: BLE001
            logger.warning("Vision OCR failed (%s): %s", getattr(v, "name", "?"), e)
        # 2) Gemini free fallback (even when enable_ocr is off)
        try:
            t, c = await image_bytes_to_text_gemini_free(jpeg)
            sc = _score_text(t)
            if t.strip():
                candidates.append((t.strip(), float(c or 0.0), sc, f"gemini:{vname}"))
            if sc > best_score:
                best_text, best_conf, best_score = t, c, sc
            if best_score >= 1400:
                break
        except Exception as e:  # noqa: BLE001
            logger.warning("Gemini OCR failed (%s): %s", getattr(v, "name", "?"), e)

    # Merge the strongest candidates (dedupe exact lines). This often upgrades a
    # "partial" OCR into a usable trader note parse.
    if candidates:
        candidates.sort(key=lambda x: x[2], reverse=True)
        top = candidates[:4]
        merged_lines: list[str] = []
        seen: set[str] = set()
        for (txt, _c, _sc, _tag) in top:
            for ln in [x.strip() for x in txt.splitlines() if x.strip()]:
                key = ln.lower().replace(" ", "")
                if key in seen:
                    continue
                seen.add(key)
                merged_lines.append(ln)
        merged = "\n".join(merged_lines).strip()
        merged_score = _score_text(merged)
        if merged and merged_score >= best_score * 0.90:
            # Confidence guess: prefer Vision if any Vision candidate exists.
            has_vision = any(tag.startswith("vision:") for *_rest, tag in top)
            conf = 0.6 if has_vision else 0.5
            # If we have many numeric tokens, bump slightly.
            if sum(1 for ch in merged if ch.isdigit()) >= 10:
                conf = min(0.8, conf + 0.1)
            return merged, conf

    if best_text.strip():
        return best_text.strip(), float(best_conf or 0.0)
    return "", 0.0
