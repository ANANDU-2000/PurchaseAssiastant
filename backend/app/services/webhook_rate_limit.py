"""Simple in-process rate limit for webhooks (per originating phone)."""

from __future__ import annotations

import time
from collections import deque
from typing import Deque

# phone -> deque of unix timestamps
_buckets: dict[str, Deque[float]] = {}
_WINDOW_SEC = 3600
_MAX_PER_WINDOW = 120


def allow(phone_key: str, *, max_per_hour: int = _MAX_PER_WINDOW) -> bool:
    """Return True if under limit, else False. Best-effort; resets hourly window."""
    now = time.time()
    q = _buckets.setdefault(phone_key, deque())
    cutoff = now - _WINDOW_SEC
    while q and q[0] < cutoff:
        q.popleft()
    if len(q) >= max_per_hour:
        return False
    q.append(now)
    return True
