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
    if getattr(settings, "enable_ocr", False):
        key = getattr(settings, "ocr_api_key", None)
        if key:
            b64 = base64.b64encode(image_bytes).decode("ascii")
            url = f"https://vision.googleapis.com/v1/images:annotate?key={key}"
            payload = {
                "requests": [
                    {
                        "image": {"content": b64},
                        "features": [{"type": "DOCUMENT_TEXT_DETECTION", "maxResults": 1}],
                    }
                ]
            }
            try:
                async with httpx.AsyncClient(timeout=60.0) as client:
                    r = await client.post(url, json=payload)
                    r.raise_for_status()
                    data = r.json()
            except Exception as e:  # noqa: BLE001
                logger.warning("Vision OCR failed: %s", e)
                data = None

            if data is not None:
                try:
                    resp0 = data["responses"][0]
                    if resp0.get("error"):
                        logger.warning("Vision OCR error payload: %s", resp0["error"])
                    else:
                        ann = resp0.get("fullTextAnnotation") or {}
                        text = (ann.get("text") or "").strip()
                        conf = float(
                            resp0.get("textAnnotations", [{}])[0].get("confidence", 0.5)
                            or 0.45
                        )
                        if text:
                            return text, conf
                except (KeyError, IndexError, TypeError, ValueError):
                    raw = json.dumps(data)[:2000] if data is not None else "null"
                    logger.warning("Vision OCR unexpected JSON: %s", raw)

    # Gemini free fallback (even when enable_ocr is off or Vision key missing)
    text, conf = await image_bytes_to_text_gemini_free(image_bytes)
    if text:
        return text, conf

    return "", 0.0
