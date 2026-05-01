"""Multipart bill scan → text (Vision when configured) → structured preview (no persistence)."""

from __future__ import annotations

import base64
import json
import logging
from typing import TYPE_CHECKING

import httpx

if TYPE_CHECKING:
    from app.config import Settings

logger = logging.getLogger(__name__)


async def image_bytes_to_text(settings: Settings, image_bytes: bytes) -> tuple[str, float]:
    """Return (extracted_text, confidence_guess).

    Uses Google Vision `DOCUMENT_TEXT_DETECTION` when `enable_ocr` and `ocr_api_key` are set;
    otherwise returns empty text.
    """
    if not getattr(settings, "enable_ocr", False):
        return "", 0.0
    key = getattr(settings, "ocr_api_key", None)
    if not key:
        return "", 0.0
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
        return "", 0.0
    try:
        resp0 = data["responses"][0]
        if resp0.get("error"):
            logger.warning("Vision OCR error payload: %s", resp0["error"])
            return "", 0.0
        ann = resp0.get("fullTextAnnotation") or {}
        text = ann.get("text") or ""
        conf = float(resp0.get("textAnnotations", [{}])[0].get("confidence", 0.5) or 0.45)
        return text.strip(), conf
    except (KeyError, IndexError, TypeError, ValueError):
        raw = json.dumps(data)[:2000]
        logger.warning("Vision OCR unexpected JSON: %s", raw)
        return "", 0.0
