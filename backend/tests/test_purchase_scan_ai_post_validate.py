from app.services.purchase_scan_ai import _post_validate


def test_post_validate_kg_unit_ignores_name_weight():
    payload, missing, warnings = _post_validate(
        {
            "supplier_name": "ABC",
            "items": [
                {
                    "name": "SUGAR 50 KG",
                    "qty": 5000,
                    "unit": "kg",
                    "purchase_rate": 56,
                    "selling_rate": 57,
                    "weight_per_unit_kg": 50,
                }
            ],
        }
    )
    assert missing == []
    assert payload["items"][0]["unit"] == "kg"
    assert payload["items"][0]["qty"] == 5000.0
    assert payload["items"][0]["weight_per_unit_kg"] is None
    assert any("ignoring name weight for KG unit" in w for w in warnings)


def test_post_validate_bag_infers_weight_from_name():
    payload, missing, warnings = _post_validate(
        {
            "supplier_name": "ABC",
            "items": [
                {
                    "name": "SUGAR 50 KG",
                    "qty": 100,
                    "unit": "bag",
                    "purchase_rate": 56,
                    "selling_rate": None,
                }
            ],
        }
    )
    assert missing == []
    assert warnings == []
    assert payload["items"][0]["weight_per_unit_kg"] == 50.0


def test_post_validate_missing_fields_are_reported():
    payload, missing, warnings = _post_validate(
        {
            "supplier_name": "",
            "items": [{"name": "", "qty": 0, "unit": "kg", "purchase_rate": 0}],
        }
    )
    assert payload is not None
    assert warnings == []
    # Supplier missing
    assert "supplier_name" in missing
    # Line missing
    assert "line_0.item_name" in missing
    assert "line_0.qty" in missing
    assert "line_0.purchase_rate" in missing

