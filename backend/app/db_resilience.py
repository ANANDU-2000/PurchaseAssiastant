"""Transient DB retries for read paths (bounded; does not swallow business-rule errors)."""

from __future__ import annotations

import asyncio
import logging
import random
from collections.abc import Awaitable, Callable
from typing import TypeVar

from sqlalchemy.exc import DBAPIError, IntegrityError, OperationalError, ProgrammingError

logger = logging.getLogger(__name__)

T = TypeVar("T")


def _transient(exc: BaseException) -> bool:
    if isinstance(exc, (TimeoutError, asyncio.TimeoutError, OSError)):
        return True
    if isinstance(exc, OperationalError):
        return True
    if isinstance(exc, DBAPIError):
        inner = getattr(exc, "orig", None)
        if inner is not None:
            name = type(inner).__name__.lower()
            if any(
                s in name
                for s in (
                    "connection",
                    "timeout",
                    "network",
                    "closed",
                    "cannot",
                    "broken",
                    "reset",
                    "transport",
                    "pool",
                )
            ):
                return True
            msg = str(inner).lower()
            return any(x in msg for x in ("connection", "timeout", "closed", "network", "refused"))
    return False


async def execute_with_retry(coro_factory: Callable[[], Awaitable[T]], *, attempts: int = 4) -> T:
    """Run coroutine_factory() up to [attempts] times on transient connection/timeout failures."""
    last: BaseException | None = None
    schedule = (0.1, 0.3, 0.9)
    for attempt in range(attempts):
        try:
            return await coro_factory()
        except Exception as e:
            last = e
            if attempt == attempts - 1 or not _transient(e):
                raise
            base = schedule[min(attempt, len(schedule) - 1)]
            backoff = base + random.uniform(0, 0.06)
            logger.warning(
                "db transient retry | attempt=%s/%s sleep=%.3fs | %s",
                attempt + 1,
                attempts,
                backoff,
                type(e).__name__,
            )
            await asyncio.sleep(backoff)
    assert last is not None
    raise last


def is_sa_infrastructure_failure(exc: BaseException) -> bool:
    """True for timeouts / disconnects — not deterministic SQL (integrity/programming errors)."""
    if isinstance(exc, (IntegrityError, ProgrammingError)):
        return False
    return _transient(exc)
