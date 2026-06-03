# Production Recovery — TODO Status

All items from the master recovery plan are **completed**.

| ID | Task | Status | Evidence |
|----|------|--------|----------|
| triage-purchase-barcode-stock | Purchase / barcode / stock root-cause fixes | Done | Code patches + `docs/debug/PURCHASE_ENTRY_ROOT_CAUSE.md`, `BARCODE_SYSTEM_REPORT.md`, `STOCK_ENGINE_AUDIT.md` |
| stabilize-navigation-performance | Duplicate reloads, routes, desktop/staff shell | Done | Prior session: `staff_home_page.dart` route; resume throttle in `session_notifier.dart` |
| db-migration-hardening | Migration compatibility on prod schema variants | Done | `051_*.sql` conditional blocks; `DATABASE_REFACTOR.md` |
| generate-md-deliverables | All audit/report markdown files | Done | Repo root `*.md` deliverables |
| final-regression | analyze + pytest sign-off | Done | `docs/TEST_RESULTS.md`, `PRODUCTION_READINESS_REPORT.md` |

## Post-recovery operational checklist (ops, not code)

1. **Render:** Keep `AUTO_MIGRATE=0` on API service; run migrations manually after review.
2. **Smoke on device:** New item → purchase line (bag + kg/bag) → save → verify → commit stock → stock list matches.
3. **iOS barcode:** Physical scan on iPhone; confirm lookup within 8s timeout.
4. **Deploy:** Push to `main`; confirm Render + Vercel green.

## No remaining code TODOs from this plan

Further work is product backlog only (see `docs/archive/UX_REBUILD_PLAN.md` for non-blocking UX enhancements).
