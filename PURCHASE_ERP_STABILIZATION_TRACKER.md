# Purchase ERP Stabilization Tracker

Current date: 2026-05-07

## Agent Rules

- Keep all financial calculations deterministic and testable.
- Do not invent purchase values, quantities, rates, units, or confidence scores.
- Preserve raw AI-extracted values separately from normalized calculation values.
- Prefer one aggregate source of truth derived from purchase item rows.
- Update this file whenever a meaningful action is started, finished, blocked, or deferred.
- Validate changes with automated tests where available.

## Current Goal

Build a production-grade AI-powered wholesale purchase ERP flow:

Image upload -> OpenAI Vision JSON extraction -> schema validation -> unit normalization -> editable preview -> DB save -> aggregate recompute -> search reindex -> dashboard/report parity.

## Progress

- [x] Created stabilization tracker.
- [x] Mapped repo surfaces: `backend`, `flutter_app`, `admin_web`.
- [x] Identified existing tests for calculations, reports, scan panel, and search parity.
- [x] Inspect backend AI extraction, purchase save, reports, dashboard, and search implementation.
- [ ] Inspect Flutter scan/review/dashboard/report/search state flow.
- [x] Implement deterministic purchase calculation engine improvements.
- [x] Implement or stabilize strict OpenAI Vision JSON pipeline.
- [x] Ensure dashboard and reports use the same aggregate source.
- [x] Fix search normalization and typo tolerance.
- [x] Deduplicate validation warnings.
- [x] Add or update tests.
- [x] Run backend tests.
- [ ] Run Flutter tests or analyzer.
- [ ] Summarize completed, pending, and verification status.

## Requirements Checklist

- [x] Strict JSON-only AI extraction contract.
- [x] Confidence scores on supplier, broker, payment terms, items, and overall response.
- [x] Unit normalization for KG, BAG, BOX, TIN, PIECE, LITRE, SACK aliases.
- [ ] Rate type detection for per kg, per bag, per box, per tin, per piece, per litre, and mixed pricing.
- [ ] Calculation of bags, boxes, tins, kg, purchase total, selling total, profit, margin, rate difference, delivery adjustment, commission, discount, and transport.
- [x] Validation warnings for malformed AI response and scan warnings deduplication.
- [ ] Editable purchase preview with recalculation.
- [x] Realtime aggregate recompute after purchase save.
- [x] Dashboard/report total parity.
- [x] Search typo alias for `suger` -> `sugar`; existing fuzzy fallback remains enabled.
- [x] AI request logging: model, duration, response received, token usage, retry count.

## Notes

- `rg` is unavailable due to access denial in this environment, so PowerShell file scanning is being used.
- Do not commit secrets. The `OPENAI_API_KEY` value must stay in environment configuration, never in source.
- Backend verification on 2026-05-07: `python -m pytest tests -q` passed, 172 tests.
