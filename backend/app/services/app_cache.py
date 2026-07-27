"""In-process TTL cache for single-instance Render deployments (no Redis required)."""

from __future__ import annotations

import hashlib
import json
import time
from collections import OrderedDict
from functools import lru_cache
from typing import Any
from uuid import UUID

_MAX_ENTRIES = 512


@lru_cache
def _settings():
    from app.config import get_settings

    return get_settings()


def stock_list_ttl_s() -> float:
    return float(_settings().cache_ttl_stock_list)


def home_overview_ttl_s() -> float:
    return float(_settings().cache_ttl_home_dashboard)


def catalog_items_ttl_s() -> float:
    return float(_settings().cache_ttl_catalog_items)


def purchase_list_ttl_s() -> float:
    return float(_settings().cache_ttl_purchase_list)


def stock_shell_bundle_ttl_s() -> float:
    return float(_settings().cache_ttl_stock_shell)


class _TtlCache:
    def __init__(self, max_entries: int = _MAX_ENTRIES) -> None:
        self._data: OrderedDict[str, tuple[float, Any]] = OrderedDict()
        self._max = max_entries

    def get(self, key: str, ttl_s: float) -> Any | None:
        row = self._data.get(key)
        if row is None:
            return None
        expires_at, value = row
        if time.monotonic() >= expires_at:
            del self._data[key]
            return None
        self._data.move_to_end(key)
        return value

    def set(self, key: str, value: Any, ttl_s: float) -> None:
        expires_at = time.monotonic() + ttl_s
        if key in self._data:
            del self._data[key]
        self._data[key] = (expires_at, value)
        while len(self._data) > self._max:
            self._data.popitem(last=False)

    def delete_prefix(self, prefix: str) -> None:
        keys = [k for k in self._data if k.startswith(prefix)]
        for k in keys:
            del self._data[k]

    def clear(self) -> None:
        self._data.clear()


_cache = _TtlCache()


def _biz_prefix(business_id: UUID | str) -> str:
    return f"biz:{business_id}:"


def cache_key_hash(parts: dict[str, Any]) -> str:
    raw = json.dumps(parts, sort_keys=True, default=str)
    return hashlib.md5(raw.encode()).hexdigest()[:16]


def get_cached(key: str, ttl_s: float) -> Any | None:
    return _cache.get(key, ttl_s)


def set_cached(key: str, value: Any, ttl_s: float) -> None:
    _cache.set(key, value, ttl_s)


def invalidate_business(business_id: UUID | str) -> None:
    """Drop all cached rows for a tenant after stock/purchase/catalog writes."""
    _cache.delete_prefix(_biz_prefix(business_id))


def stock_list_cache_key(business_id: UUID | str, query: dict[str, Any]) -> str:
    return f"{_biz_prefix(business_id)}stock:list:{cache_key_hash(query)}"


def home_overview_cache_key(business_id: UUID | str, query: dict[str, Any]) -> str:
    return f"{_biz_prefix(business_id)}home:overview:{cache_key_hash(query)}"


def catalog_items_list_cache_key(business_id: UUID | str, query: dict[str, Any]) -> str:
    return f"{_biz_prefix(business_id)}catalog:list:{cache_key_hash(query)}"


def catalog_compact_cache_key(business_id: UUID | str) -> str:
    return f"{_biz_prefix(business_id)}catalog:compact"


def purchase_list_cache_key(business_id: UUID | str, query: dict[str, Any]) -> str:
    return f"{_biz_prefix(business_id)}purchases:list:{cache_key_hash(query)}"


def stock_shell_bundle_cache_key(business_id: UUID | str, query: dict[str, Any]) -> str:
    return f"{_biz_prefix(business_id)}stock:shell:{cache_key_hash(query)}"


def clear_all_caches_for_tests() -> None:
    """Test helper — wipe in-process cache."""
    _cache.clear()
