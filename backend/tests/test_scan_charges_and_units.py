from app.services.bill_line_extract import extract_purchase_lines_from_text
from app.services.ocr_parser import extract_header_charges, extract_item_rows


def test_extract_header_charges_delhead_billty_freight():
    text = "surag\nkkkk\nsugar 50kg\n100 bag p56 s57\ndelhead 36 billty 18 freight 500"
    ch = extract_header_charges(text)
    assert ch["delivered_rate"] == 36.0
    assert ch["billty_rate"] == 18.0
    assert ch["freight_amount"] == 500.0
    assert ch["freight_type"] == "separate"


def test_bill_line_extract_supports_box_and_piece():
    text = "10 box WHEAT 1200\n5 pc OIL 90"
    raw = extract_purchase_lines_from_text(text)
    assert raw[0]["unit"] == "box"
    assert raw[1]["unit"] == "unit"


def test_extract_item_rows_accepts_box_unit():
    text = "10 box WHEAT 1200"
    rows, missing = extract_item_rows(text)
    assert not missing
    assert rows[0]["unit"] == "box"
