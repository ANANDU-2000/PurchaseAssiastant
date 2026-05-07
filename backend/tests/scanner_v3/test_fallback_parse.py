import asyncio
import uuid

from app.services.scanner_v2.types import Charges, Match, ScanMeta, ScanResult, Totals
from app.services.scanner_v2 import pipeline as scanner_v2_pipeline
from app.services.scanner_v3.pipeline import _fallback_parse_text, consume_result, start_scan, update_result


class _Settings:
    openai_model_parse = "gpt-test"


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


def test_v3_review_update_can_be_consumed_by_confirm_bridge():
    business_id = uuid.uuid4()
    token = start_scan(business_id=business_id, image_bytes=b"fake", settings=_Settings())
    supplier_id = uuid.uuid4()
    reviewed = ScanResult(
        supplier=Match(
            raw_text="Surag",
            matched_id=supplier_id,
            matched_name="Surag",
            confidence=0.99,
            match_state="auto",
            candidates=[],
        ),
        broker=None,
        items=[],
        charges=Charges(),
        totals=Totals(),
        confidence_score=0.99,
        needs_review=False,
        warnings=[],
        scan_token=token,
        scan_meta=ScanMeta(),
    )

    assert update_result(business_id=business_id, scan_token=token, scan=reviewed)
    consumed = consume_result(business_id=business_id, scan_token=token)
    assert consumed is not None
    assert consumed.scan_token == token
    assert consumed.supplier.matched_id == supplier_id
    assert consume_result(business_id=business_id, scan_token=token) is None


def test_openai_image_parser_sends_image_and_returns_json(monkeypatch):
    async def fake_keys(_settings, _db):
        return {"openai": "sk-test", "gemini": None, "groq": None}

    captured = {}

    class _Response:
        status_code = 200

        def json(self):
            return {
                "choices": [
                    {
                        "message": {
                            "content": (
                                '{"supplier_name":"Surag","broker_name":null,'
                                '"items":[{"name":"Sugar 50kg","unit_type":"BAG",'
                                '"weight_per_unit_kg":50,"bags":100,"total_kg":null,'
                                '"qty":100,"purchase_rate":57,"selling_rate":58,'
                                '"delivered_rate":null,"billty_rate":null,"notes":null}],'
                                '"charges":{"delivered_rate":56,"billty_rate":null,'
                                '"freight_amount":null,"freight_type":null,"discount_percent":null},'
                                '"broker_commission":null,"payment_days":7}'
                            )
                        }
                    }
                ]
            }

    class _Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

        async def post(self, url, *, headers, json):
            captured["url"] = url
            captured["headers"] = headers
            captured["json"] = json
            return _Response()

    monkeypatch.setattr(scanner_v2_pipeline, "resolve_provider_keys", fake_keys)
    monkeypatch.setattr(scanner_v2_pipeline.httpx, "AsyncClient", _Client)

    raw, meta = asyncio.run(
        scanner_v2_pipeline._openai_parse_scanner_image_payload(
            image_bytes=b"fake image",
            settings=_Settings(),
            db=object(),
        )
    )

    assert raw is not None
    assert raw["supplier_name"] == "Surag"
    assert raw["items"][0]["name"] == "Sugar 50kg"
    assert meta["provider_used"] == "openai_image"
    assert captured["url"] == "https://api.openai.com/v1/chat/completions"
    assert captured["json"]["response_format"] == {"type": "json_object"}
    content = captured["json"]["messages"][1]["content"]
    assert content[1]["type"] == "image_url"
    assert content[1]["image_url"]["url"].startswith("data:image/jpeg;base64,")
