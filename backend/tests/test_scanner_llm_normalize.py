"""Unit tests for LLM scan payload normalization helpers."""

from datetime import date

from app.services.scanner_v2.pipeline import (
    compute_bill_fingerprint,
    llm_payload_is_not_a_bill,
    normalize_llm_scan_dict,
    parse_bill_date_maybe,
)


def test_llm_payload_is_not_a_bill() -> None:
    assert llm_payload_is_not_a_bill({"error": "not_a_bill"})
    assert llm_payload_is_not_a_bill({"error": "NOT_A_BILL"})
    assert not llm_payload_is_not_a_bill({"supplier_name": "X"})
    assert not llm_payload_is_not_a_bill(None)


def test_normalize_llm_scan_dict_aliases() -> None:
    raw = normalize_llm_scan_dict(
        {
            "items": [
                {
                    "item_name": "SUGAR",
                    "unit": "bag",
                    "total_weight_kg": 5000,
                    "qty": 100,
                },
                {"name": "OIL", "unit": "loose", "qty": 10},
            ]
        }
    )
    items = raw["items"]
    assert items[0]["name"] == "SUGAR"
    assert items[0]["unit_type"] == "BAG"
    assert items[0]["total_kg"] == 5000
    assert items[1]["unit_type"] == "KG"


def test_compute_bill_fingerprint_and_date() -> None:
    fp = compute_bill_fingerprint("INV 1", "2026-05-08", "Acme Traders")
    assert fp == "inv12026-05-08acmetraders"
    assert parse_bill_date_maybe("2026-05-08") == date(2026, 5, 8)
    assert parse_bill_date_maybe(None) is None
