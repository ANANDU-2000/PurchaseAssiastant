# 81 — AI_FIELD_VALIDATION

## Goal
Validate AI output before creating a purchase:
- numeric fields are numeric
- units follow package rules
- bag math is consistent

## Current validation points
- Backend:
  - Bag/kg normalization: `backend/app/services/scanner_v2/bag_logic.py`
  - Trade purchase creation validation: `backend/app/schemas/trade_purchases.py`
- Flutter:
  - Purchase draft validation (wizard) blocks save with explicit reasons.

## Trader rule reminders
- `bag` must have a real kg-per-bag signal (from name, catalog, or manual).
- `box` / `tin` are count-only.

