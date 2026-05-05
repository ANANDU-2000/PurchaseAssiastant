# SPEC 14 — SMOKE TESTS (FULL WORKSPACE VALIDATION)
> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS
| Task | Status |
|------|--------|
| Flutter `flutter analyze` (full app) | ✅ Done |
| Backend Python compile check | ✅ Done |
| Backend pytest smoke (if tests present) | ✅ Done (98 passed) |

---

## WHAT TO DO
### ❌ TASK 14-A: Flutter analyze
Run `flutter analyze` from `flutter_app/`.

### ❌ TASK 14-B: Backend compile + tests
Run `python -m compileall backend/app`.
If `backend/tests/` exists, run `pytest -q`.

---

## VALIDATION
- [ ] Flutter analyze passes
- [ ] Backend compile passes
- [ ] Backend tests pass (if present)

