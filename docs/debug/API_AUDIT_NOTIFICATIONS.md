# API Audit — Phase 7: Notifications

**Date:** 2026-07-28  
**Router:** `backend/app/routers/notifications.py`  
**Jobs:** `scheduled_notification_jobs.py`

## Prod evidence

- `GET …/notifications?page=N` → **200** (sometimes pages 1–4; occasional **401** then retry OK)
- No notifications **5xx** in sampled window
- Mutations already `await db.commit()`

## Findings

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| NOTIF-H1 | High | List applied `target_roles` **after** `LIMIT` → short pages; Flutter stops paging when `chunk.length < per_page` | **Fixed** — SQL role filter before LIMIT |
| NOTIF-H2 | High | `unread-count` / `summary` ignored `target_roles` → badge ≠ list | **Fixed** — same role SQL |
| NOTIF-H3 | High | Idle delivery scan notified on `cancelled`/`deleted`/`draft` purchases | **Fixed** |
| NOTIF-M1 | Medium | List ~500ms under load | Track |
| NOTIF-L1 | Low | `due_soon_reminder` scheduler tick is a no-op stub | Track |

## Tests

- `tests/test_notifications.py` — role-targeted row hidden from list/unread/summary
- `tests/test_scheduled_notification_jobs.py` — cancelled idle delivery skipped

## Open Critical

**None** for Notifications after this pass.

## Next

Users → Warehouse/Ops → Exports → rest.
