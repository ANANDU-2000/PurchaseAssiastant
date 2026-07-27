"""Minimal JSON helpers for purchase scan AI parsing.

The general in-app assistant was removed for Harisree, but the purchase bill
scanner still needs provider-specific strict JSON helpers.
"""

from __future__ import annotations

import json
import re
from typing import Any

import httpx

from app.config import Settings


def _parse_json_loose(text: str) -> dict[str, Any]:
    s = (text or "").strip()
    if not s:
        return {}
    if s.startswith("```"):
        s = re.sub(r"^```(?:json)?\s*", "", s, flags=re.IGNORECASE)
        s = re.sub(r"\s*```$", "", s)
    try:
        d = json.loads(s)
        return d if isinstance(d, dict) else {}
    except Exception:
        pass
    start = s.find("{")
    end = s.rfind("}")
    if start >= 0 and end > start:
        try:
            d = json.loads(s[start : end + 1])
            return d if isinstance(d, dict) else {}
        except Exception:
            return {}
    return {}


async def _gemini_json(prompt: str, settings: Settings, api_key: str) -> dict[str, Any] | None:
    model = settings.google_ai_model or "gemini-1.5-flash"
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={api_key}"
    )
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0,
            "response_mime_type": "application/json",
        },
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(url, json=payload)
        res.raise_for_status()
    data = res.json()
    text = (
        data.get("candidates", [{}])[0]
        .get("content", {})
        .get("parts", [{}])[0]
        .get("text", "")
    )
    return _parse_json_loose(text)


async def _groq_json(prompt: str, settings: Settings, api_key: str) -> dict[str, Any] | None:
    payload = {
        "model": settings.groq_model or "llama-3.1-70b-versatile",
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": "Return only valid JSON."},
            {"role": "user", "content": prompt},
        ],
    }
    headers = {"Authorization": f"Bearer {api_key}"}
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers=headers,
            json=payload,
        )
        res.raise_for_status()
    data = res.json()
    text = data.get("choices", [{}])[0].get("message", {}).get("content", "")
    return _parse_json_loose(text)

