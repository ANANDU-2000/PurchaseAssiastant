# Phase 1 — ordered tasks (live checklist)

Run tests after each major step: `cd backend && .venv\Scripts\python -m pytest tests\ -q`  
Flutter: `cd flutter_app && flutter analyze lib/...` on touched files.

**Phase 1 gate (recorded):** `pip install -r backend/requirements.txt` (includes `requests`, `greenlet` for tests), then `cd backend && python -m pytest tests/ -q` → **9 passed**; `cd flutter_app && flutter analyze lib` → **No issues found**. Device/web smoke is manual.

| # | Task | Status |
|---|------|--------|
| 1 | **Preview → Save enforced:** server issues `preview_token` on `confirm:false`; `confirm:true` requires valid token + matching payload hash. App: Preview enables Save. | Done |
| 2 | **Landing / duplicate / anomaly on server:** auto or validate landing vs buy + shared costs; enforce duplicate policy; optional price anomaly flag (align with PRD). | Done |
| 3 | **Master data:** categories + items CRUD (API + Flutter), linked to lines where applicable. | Done |
| 4 | **Dashboard:** summary cards, alerts, quick actions, pull-to-refresh / polling as spec’d. | Done |
| 5 | **Gate:** full pytest + flutter analyze on Phase 1 paths; smoke on device/web. | Done |

Notes:

- WhatsApp flows call `persist_confirmed_entry` directly (preview happens in chat); HTTP app flow uses `preview_token`.
- Multi-instance production: replace in-memory preview store with Redis (same TTL semantics).
