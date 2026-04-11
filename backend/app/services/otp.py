"""OTP storage: Redis when REDIS_URL is reachable, else in-process (single-instance dev)."""

from __future__ import annotations

import logging
import random
import time
from typing import TYPE_CHECKING, Protocol

from app.config import Settings

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)


class OtpStore(Protocol):
    async def set_code(self, phone: str, code: str, ttl_seconds: int = 600) -> None: ...
    async def get_code(self, phone: str) -> str | None: ...
    async def delete(self, phone: str) -> None: ...


class MemoryOtpStore:
    def __init__(self) -> None:
        self._data: dict[str, tuple[str, float]] = {}

    async def set_code(self, phone: str, code: str, ttl_seconds: int = 600) -> None:
        self._data[phone] = (code, time.time() + ttl_seconds)

    async def get_code(self, phone: str) -> str | None:
        row = self._data.get(phone)
        if not row:
            return None
        code, exp = row
        if time.time() > exp:
            del self._data[phone]
            return None
        return code

    async def delete(self, phone: str) -> None:
        self._data.pop(phone, None)


class RedisOtpStore:
    """OTP codes in Redis with TTL (multi-instance safe)."""

    def __init__(self, redis_url: str) -> None:
        import redis.asyncio as redis

        self._redis = redis.from_url(redis_url, decode_responses=True)
        self._prefix = "hexa:otp:"

    async def set_code(self, phone: str, code: str, ttl_seconds: int = 600) -> None:
        await self._redis.setex(f"{self._prefix}{phone}", ttl_seconds, code)

    async def get_code(self, phone: str) -> str | None:
        return await self._redis.get(f"{self._prefix}{phone}")

    async def delete(self, phone: str) -> None:
        await self._redis.delete(f"{self._prefix}{phone}")


memory_otp_store = MemoryOtpStore()
_redis_store: RedisOtpStore | None = None


def get_otp_store(settings: Settings) -> OtpStore:
    """Return Redis-backed store when REDIS_URL is set, else memory."""
    global _redis_store
    if not settings.redis_url:
        return memory_otp_store
    if _redis_store is None:
        try:
            _redis_store = RedisOtpStore(settings.redis_url)
            logger.info("OTP store: Redis")
        except Exception as e:  # noqa: BLE001
            logger.warning("OTP store: Redis unavailable (%s), using memory", e)
            return memory_otp_store
    return _redis_store


def generate_otp() -> str:
    return f"{random.randint(0, 999999):06d}"


async def send_otp(settings: Settings, store: OtpStore, phone: str) -> str:
    if settings.dev_otp_code:
        code = settings.dev_otp_code
    else:
        code = generate_otp()
    await store.set_code(phone, code)
    # Production: plug SMS provider (OTP_PROVIDER / OTP_API_KEY) here
    return code
