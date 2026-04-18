"""Heuristic bill line extraction from pasted text."""

from app.services.bill_line_extract import extract_purchase_lines_from_text


def test_extract_pat_a_qty_unit_name_rate():
    text = "10 bag Basmati @ 1200"
    rows = extract_purchase_lines_from_text(text)
    assert len(rows) == 1
    assert rows[0]["item_name"] == "Basmati"
    assert rows[0]["qty"] == 10.0
    assert rows[0]["unit"] == "bag"
    assert rows[0]["landing_cost"] == 1200.0


def test_extract_pat_b_name_qty_unit_rate():
    text = "Wheat 5 kg 42"
    rows = extract_purchase_lines_from_text(text)
    assert len(rows) == 1
    assert rows[0]["item_name"] == "Wheat"
    assert rows[0]["qty"] == 5.0
    assert rows[0]["unit"] == "kg"
    assert rows[0]["landing_cost"] == 42.0


def test_extract_pat_c_name_qty_rate_default_kg():
    text = "Sugar 12 450"
    rows = extract_purchase_lines_from_text(text)
    assert len(rows) == 1
    assert rows[0]["item_name"] == "Sugar"
    assert rows[0]["qty"] == 12.0
    assert rows[0]["unit"] == "kg"
    assert rows[0]["landing_cost"] == 450.0


def test_extract_multiline():
    text = "2 bags Rice 2000\nMaida 10 kg 55"
    rows = extract_purchase_lines_from_text(text)
    assert len(rows) == 2
    assert rows[0]["item_name"] == "Rice"
    assert rows[1]["item_name"] == "Maida"


def test_empty_text():
    assert extract_purchase_lines_from_text("") == []
    assert extract_purchase_lines_from_text("   \n  ") == []
