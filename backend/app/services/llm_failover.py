"""Ordered LLM failover: Gemini -> Groq -> OpenAI for in-app assistant calls."""

from __future__ import annotations

from typing import Any, Awaitable, Callable

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.services.platform_credentials import (
    effective_google_ai_key,
    effective_groq_key,
    effective_openai_key,
)

ProviderFn = Callable[..., Awaitable[Any]]


async def resolve_provider_keys(
    settings: Settings,
    db: AsyncSession,
) -> dict[str, str | None]:
    """Effective keys (env or platform_integration), never logged."""
    return {
        "gemini": await effective_google_ai_key(settings, db),
        "groq": await effective_groq_key(settings, db),
        "openai": await effective_openai_key(settings, db),
    }


def any_llm_key(keys: dict[str, str | None]) -> bool:
    return bool(
        (keys.get("gemini") or "").strip()
        or (keys.get("groq") or "").strip()
        or (keys.get("openai") or "").strip()
    )


async def run_ordered_failover(
    *,
    runners: list[tuple[str, str | None, ProviderFn]],
) -> tuple[Any | None, dict[str, Any]]:
    """
    Try each (name, key, async_fn) in order. Skip if key missing.
    Returns (first truthy result, meta with attempts). Empty string counts as failure.
    """
    attempts: list[dict[str, Any]] = []
    tried_with_key = 0
    for name, key, fn in runners:
        k = (key or "").strip()
        if not k:
            attempts.append({"provider": name, "skipped": True, "reason": "no_key"})
            continue
        tried_with_key += 1
        try:
            out = await fn()
            if out is not None and not (isinstance(out, str) and not out.strip()):
                attempts.append({"provider": name, "ok": True})
                return out, {
                    "provider_used": name,
                    "failover": attempts,
                    "failover_used": tried_with_key > 1,
                }
            attempts.append({"provider": name, "ok": False, "reason": "empty_response"})
        except Exception as e:  # noqa: BLE001
            attempts.append(
                {
                    "provider": name,
                    "ok": False,
                    "error": str(e)[:300],
                }
            )
    return None, {"provider_used": None, "failover": attempts, "failover_used": False}
