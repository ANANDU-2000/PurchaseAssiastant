"""Multipart bill scan → raw text via OpenAI Vision only (fallback when image→JSON fails).

Purchase bills MUST NOT use third-party OCR (Google Vision, Gemini image extract, etc.).
See MASTER_AGENT_RULES / context/rules/MASTER_AGENT_RULES.md.
"""

from __future__ import annotations

import base64
import logging
from typing import TYPE_CHECKING

import httpx

if TYPE_CHECKING:
    from app.config import Settings

logger = logging.getLogger(__name__)


def _score_text(text: str) -> int:
    """Simple heuristic score: prefer longer, more numeric-heavy transcripts."""
    t = (text or "").strip()
    if not t:
        return 0
    digits = sum(1 for ch in t if ch.isdigit())
    letters = sum(1 for ch in t if ch.isalpha())
    lines = t.count("\n") + 1
    return len(t) + digits * 3 + min(40, letters) + min(30, lines * 3)


async def image_bytes_to_text_openai(
    image_bytes: bytes,
    *,
    api_key: str | None = None,
    model: str = "gpt-4.1-mini",
) -> tuple[str, float]:
    """OpenAI Vision: extract raw bill text from an image (no structured JSON).

    Used only as a fallback when direct image→JSON scanning fails; parsing is still LLM-based downstream.
    """
    key = (api_key or "").strip()
    if not key or not image_bytes:
        return "", 0.0
    b64 = base64.b64encode(image_bytes).decode("ascii")
    payload = {
        "model": model,
        "max_tokens": 1200,
        "temperature": 0,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": (
                            "Extract raw text from this purchase bill or handwritten purchase note. "
                            "Preserve supplier names, item names, quantities, units, rates, charges, "
                            "and payment terms. Return only the extracted text."
                        ),
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{b64}",
                            "detail": "low",
                        },
                    },
                ],
            }
        ],
    }
    try:
        async with httpx.AsyncClient(timeout=45.0) as client:
            res = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json=payload,
            )
            res.raise_for_status()
            data = res.json()
        text = data["choices"][0]["message"]["content"]
        text = (text or "").strip() if isinstance(text, str) else ""
        return text, 0.75 if text else 0.0
    except Exception as e:  # noqa: BLE001
        logger.warning("OpenAI vision text extract failed: %s", e)
        return "", 0.0


async def image_bytes_to_text(settings: Settings, image_bytes: bytes) -> tuple[str, float]:
    """Return (extracted_text, confidence_guess) using OpenAI Vision only.

    Runs optional preprocess variants; each variant is sent to OpenAI Vision.
    Google Vision / Gemini image OCR are intentionally not used for purchase bills.
    """
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
    candidates: list[tuple[str, float, int, str]] = []

    model = getattr(settings, "openai_model_parse", "gpt-4.1-mini")
    api_key = getattr(settings, "openai_api_key", None)

    for v in variants:
        jpeg = getattr(v, "jpeg_bytes", b"") or b""
        if not jpeg:
            continue
        vname = getattr(v, "name", "orig")
        try:
            t, c = await image_bytes_to_text_openai(jpeg, api_key=api_key, model=model)
            sc = _score_text(t)
            if t.strip():
                candidates.append((t.strip(), float(c or 0.0), sc, f"openai:{vname}"))
            if sc > best_score:
                best_text, best_conf, best_score = t, c, sc
            if best_score >= 1400:
                break
        except Exception as e:  # noqa: BLE001
            logger.warning("OpenAI vision extract failed (%s): %s", getattr(v, "name", "?"), e)

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
            conf = 0.55
            if sum(1 for ch in merged if ch.isdigit()) >= 10:
                conf = min(0.8, conf + 0.1)
            return merged, conf

    if best_text.strip():
        return best_text.strip(), float(best_conf or 0.0)
    return "", 0.0
