"""Simple in-process rate limit for webhooks (per originating phone)."""

from __future__ import annotations

import time
from collections import deque
from typing import Deque

# phone -> deque of unix timestamps
_buckets: dict[str, Deque[float]] = {}
_WINDOW_SEC = 3600
_MAX_PER_WINDOW = 120

# Short window (abuse protection): per-minute burst cap
_minute_buckets: dict[str, Deque[float]] = {}
_MINUTE_WINDOW_SEC = 60
_DEFAULT_MAX_PER_MINUTE = 20


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


def allow_per_minute(
    phone_key: str, *, max_per_minute: int = _DEFAULT_MAX_PER_MINUTE
) -> bool:
    """Sliding window: at most ``max_per_minute`` requests per rolling 60s (per key)."""
    now = time.time()
    q = _minute_buckets.setdefault(phone_key, deque())
    cutoff = now - _MINUTE_WINDOW_SEC
    while q and q[0] < cutoff:
        q.popleft()
    if len(q) >= max_per_minute:
        return False
    q.append(now)
    return True


def allow_whatsapp_inbound(
    phone_key: str, *, max_per_minute: int = _DEFAULT_MAX_PER_MINUTE, max_per_hour: int = _MAX_PER_WINDOW
) -> bool:
    """Both minute burst and hourly cap must pass; single commit (no partial increments)."""
    now = time.time()
    mk = f"min:{phone_key}"
    hk = f"hr:{phone_key}"
    mq = _minute_buckets.setdefault(mk, deque())
    hq = _buckets.setdefault(hk, deque())
    m_cut = now - _MINUTE_WINDOW_SEC
    h_cut = now - _WINDOW_SEC
    while mq and mq[0] < m_cut:
        mq.popleft()
    while hq and hq[0] < h_cut:
        hq.popleft()
    if len(mq) >= max_per_minute or len(hq) >= max_per_hour:
        return False
    mq.append(now)
    hq.append(now)
    return True
