"""Simple in-process sliding-window rate limiter for OTP and similar endpoints."""

from __future__ import annotations

import time
from collections import defaultdict
from threading import Lock


class SlidingWindowLimiter:
    def __init__(self, max_requests: int, window_seconds: float = 60.0) -> None:
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._lock = Lock()
        self._buckets: dict[str, list[float]] = defaultdict(list)

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        with self._lock:
            bucket = self._buckets[key]
            cutoff = now - self.window_seconds
            while bucket and bucket[0] < cutoff:
                bucket.pop(0)
            if len(bucket) >= self.max_requests:
                return False
            bucket.append(now)
            return True


otp_ip_limiter = SlidingWindowLimiter(max_requests=10, window_seconds=60.0)
