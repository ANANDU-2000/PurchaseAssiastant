import time

from app.services.webhook_rate_limit import allow_whatsapp_inbound


def test_allow_whatsapp_inbound_minute_cap():
    key = f"test:{time.time_ns()}"
    for _ in range(20):
        assert allow_whatsapp_inbound(key, max_per_minute=20, max_per_hour=500) is True
    assert allow_whatsapp_inbound(key, max_per_minute=20, max_per_hour=500) is False
