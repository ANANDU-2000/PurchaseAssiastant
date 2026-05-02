"""Bounded waits for curated read aggregations — never intercept mutations."""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from typing import TypeVar

from app.config import get_settings

T = TypeVar("T")


async def run_read_budget_bounded(
    factory: Callable[[], Awaitable[T]],
    *,
    timeout_seconds: float | None = None,
) -> tuple[bool, T | None]:
    """
    Run an async aggregation under asyncio timeout.

    Returns (True, value) when the factory completes in time,
    or (False, None) when it times out. Other exceptions propagate.
    """
    cfg = get_settings()
    limit = cfg.api_read_budget_seconds if timeout_seconds is None else timeout_seconds
    if limit <= 0:
        return True, await factory()
    try:
        return True, await asyncio.wait_for(factory(), timeout=limit)
    except TimeoutError:
        return False, None
