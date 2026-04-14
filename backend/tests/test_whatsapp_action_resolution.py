import asyncio
import uuid
from unittest.mock import AsyncMock

from app.services.whatsapp_action_resolution import (
    build_entry_create_request,
    merge_kv_into_create_data,
)


def test_merge_kv_into_create_data():
    base = {"item": "Rice"}
    merged = merge_kv_into_create_data(base, {"qty": "10", "buy": "50", "land": "55"})
    assert merged["qty"] == "10"
    assert merged["buy_price"] == "50"
    assert merged["landing_cost"] == "55"


def test_build_entry_rejects_nonpositive_buy_price():
    async def run():
        req, missing = await build_entry_create_request(
            AsyncMock(),
            uuid.uuid4(),
            {
                "item": "Rice",
                "qty": 10,
                "unit": "kg",
                "buy_price": 0,
                "landing_cost": 100,
            },
        )
        assert req is None
        assert "buy_price" in missing

    asyncio.run(run())
