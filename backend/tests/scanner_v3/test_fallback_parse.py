from app.services.scanner_v3.pipeline import _fallback_parse_text


def test_fallback_parse_critical_note():
    text = """
Surag
kkk
Sugar 50kg
100 bags
57 58
delivered 56
7 days
""".strip()
    out = _fallback_parse_text(text)
    assert out["supplier_name"].lower().startswith("sur")
    assert out["broker_name"].lower().startswith("kk")
    assert out["payment_days"] == 7
    assert out["charges"]["delivered_rate"] == 56
    assert out["items"], out
    it = out["items"][0]
    assert "sugar" in it["name"].lower()
    assert it["unit_type"] == "BAG"
    assert it["weight_per_unit_kg"] == 50
    assert it["bags"] == 100
    assert it["purchase_rate"] == 57
    assert it["selling_rate"] == 58


def test_fallback_parse_labeled_supplier_broker_and_rates():
    text = """
Supplier: Surag
Broker: kkk
Sugar 50kg
Qty: 100 bags
Purchase rate: 57
Selling rate: 58
Delivered rate: 56
Payment days: 7
""".strip()
    out = _fallback_parse_text(text)
    assert "surag" in (out["supplier_name"] or "").lower()
    assert "kkk" in (out["broker_name"] or "").lower()
    assert out["payment_days"] == 7
    assert out["charges"]["delivered_rate"] == 56
    it = out["items"][0]
    assert it["bags"] == 100
    assert it["purchase_rate"] == 57
    assert it["selling_rate"] == 58

