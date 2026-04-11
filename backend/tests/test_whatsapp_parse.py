from app.services import whatsapp_flow as wf


def test_parse_multiline_entry_draft():
    text = """
item: Test Oil
qty: 10
unit: kg
buy: 100
land: 105
date: 2025-04-01
""".strip()
    req = wf._parse_entry_text(text)
    assert req is not None
    assert req.entry_date.isoformat() == "2025-04-01"
    assert req.lines[0].item_name == "Test Oil"
    assert req.lines[0].qty == 10
    assert req.lines[0].unit == "kg"


def test_parse_rejects_bad_unit():
    text = "item: X\nqty: 1\nunit: liter\nbuy: 1\nland: 1"
    assert wf._parse_entry_text(text) is None
