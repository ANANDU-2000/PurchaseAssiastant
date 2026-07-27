"""In-process app_cache hit/miss and invalidation."""

import uuid

from app.read_cache_generation import bump_trade_read_caches_for_business, trade_read_cache_generation
from app.services.app_cache import (
    catalog_items_list_cache_key,
    clear_all_caches_for_tests,
    get_cached,
    invalidate_business,
    purchase_list_cache_key,
    set_cached,
    stock_list_cache_key,
    stock_list_ttl_s,
)


def test_cache_set_and_get_roundtrip():
    clear_all_caches_for_tests()
    key = "test:key"
    set_cached(key, {"ok": True}, stock_list_ttl_s())
    assert get_cached(key, stock_list_ttl_s()) == {"ok": True}


def test_invalidate_business_clears_tenant_keys():
    clear_all_caches_for_tests()
    bid = uuid.uuid4()
    key = stock_list_cache_key(bid, {"page": 1})
    set_cached(key, {"items": []}, stock_list_ttl_s())
    assert get_cached(key, stock_list_ttl_s()) is not None
    invalidate_business(bid)
    assert get_cached(key, stock_list_ttl_s()) is None


def test_bump_trade_read_changes_cache_generation():
    clear_all_caches_for_tests()
    bid = uuid.uuid4()
    gen_before = trade_read_cache_generation(bid)
    query = {"gen": gen_before, "page": 1}
    key = purchase_list_cache_key(bid, query)
    set_cached(key, {"items": []}, stock_list_ttl_s())
    assert get_cached(key, stock_list_ttl_s()) is not None

    bump_trade_read_caches_for_business(bid)
    gen_after = trade_read_cache_generation(bid)
    assert gen_after > gen_before

    new_key = purchase_list_cache_key(bid, {"gen": gen_after, "page": 1})
    assert new_key != key
    assert get_cached(new_key, stock_list_ttl_s()) is None


def test_catalog_list_cache_key_includes_filters():
    bid = uuid.uuid4()
    k1 = catalog_items_list_cache_key(bid, {"page": 1, "category_id": "a"})
    k2 = catalog_items_list_cache_key(bid, {"page": 1, "category_id": "b"})
    assert k1 != k2
