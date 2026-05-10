"""ScanResult / ItemRow wire defaults (scanner confidence surface)."""

from __future__ import annotations

import uuid

from app.services.scanner_v2.types import ItemRow, Match, ScanResult


def test_scan_result_has_confidence_and_review_flags() -> None:
    sid = uuid.uuid4()
    sr = ScanResult(
        supplier=Match(raw_text="ACME", matched_id=sid, matched_name="ACME", confidence=0.9, match_state="auto"),
        items=[
            ItemRow(
                raw_name="RICE 50KG",
                matched_catalog_item_id=sid,
                matched_name="RICE",
                confidence=0.72,
                match_state="needs_confirmation",
            )
        ],
        confidence_score=0.8,
        needs_review=True,
        scan_token="test-token",
    )
    assert sr.confidence_score == 0.8
    assert sr.items[0].confidence == 0.72
    assert sr.items[0].match_state == "needs_confirmation"
