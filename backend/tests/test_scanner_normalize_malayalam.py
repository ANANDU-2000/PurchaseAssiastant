"""Matcher normalization keeps Malayalam script for fuzzy passes (scanner hardening)."""

from __future__ import annotations

from app.services.scanner_v2.matcher import manglish_normalize, normalize


def test_normalize_lowercases_latin_keeps_malayalam_codepoints() -> None:
    raw = "RICE  \u0d2a\u0d28\u0d28"  # Malayalam letters + Latin
    n = normalize(raw)
    assert "rice" in n
    assert any("\u0d00" <= ch <= "\u0d7f" for ch in n)


def test_manglish_normalize_applies_trader_vocabulary() -> None:
    n = normalize("Pacha Ari 50KG")
    out = manglish_normalize(n)
    assert "raw" in out and "rice" in out
