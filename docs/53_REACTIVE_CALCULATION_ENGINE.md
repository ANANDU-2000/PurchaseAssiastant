# 53 — REACTIVE_CALCULATION_ENGINE

## Goal
All totals come from one canonical calculation engine, shared by wizard, reports, and PDF.

## Flutter SSOT
- Line math: `lineMoney(...)` / `lineMoneyDecimal(...)`
- Totals: `computeTradeTotals(...)`
- Header commission: `headerCommissionAddOnDecimal(...)`
- File: `flutter_app/lib/core/calc_engine.dart`

## Backend SSOT
- Line money: `_line_money(...)`
- Totals: `compute_totals(...)`
- Header commission: `_header_commission_rupees(...)`
- File: `backend/app/services/trade_purchase_service.py`

