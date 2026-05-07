# 94 — SUPPLIER_MATCHING_ENGINE

## Goal

Supplier detection must succeed even with minor spelling differences.

Examples that must match:

- `surag` ↔ `suraj` ↔ `suragh`

## Backend matching

- Matching happens after semantic parse:
  - `backend/app/services/scanner_v2/pipeline.py::_match_supplier_broker`
- Normalization + alias learning:
  - `backend/app/services/scanner_v2/matcher.py`
  - `POST /v1/me/scan-purchase-v2/correct` persists user corrections as aliases

## Required behavior

- Return best candidate list (for UI suggestions)
- Never return “0% confidence + blank”
- If unresolved:
  - show “Supplier unclear” + top candidates + quick create

