## VALIDATION (QUALITY GATE)

This file is the **quality gate**. It prevents shipping broken work.

Rule: **Do not mark a task complete** in `context/00_MASTER_TASKS.md` until **ALL** checks below pass.

If **ANY** check fails:
- Do **NOT** mark the task complete
- Fix immediately
- Re-run validation

Only if **ALL PASS**:
- Mark the task ✅ complete in `context/00_MASTER_TASKS.md`
- Update `context/99_PROGRESS_TRACKER.md` (Status: COMPLETE + next task)

---

## VALIDATION RULES

### UI
- [ ] No overflow (no yellow/black overflow stripes)
- [ ] No overlap (keyboard, bottom bars, sheets, dialogs)
- [ ] Proper spacing and readable typography
- [ ] Mobile viewport tested: **iPhone 16 Pro** (393×852pt) with safe areas

### LOGIC
- [ ] All calculations correct (qty/weight/cost/discount/commission/etc as per spec)
- [ ] No duplication (no double-add, double-save, repeated list rows)
- [ ] No wrong values (IDs, units, totals, rounding)

### DB
- [ ] Correct data saved (payload matches schema; correct foreign keys)
- [ ] No type errors
- [ ] No null crashes (backend + client null safety, optional fields handled)

### ERROR HANDLING
- [ ] All inputs validated (required fields, numeric ranges, formats)
- [ ] No crashes on bad inputs / network failures
- [ ] Clear user-visible messages (SnackBar/inline errors; no raw stack traces)

### PERFORMANCE
- [ ] Fast load (no obvious jank on initial render)
- [ ] No lag on typing/searching/scrolling

---

## VALIDATION PROCEDURE (PRACTICAL)

Use these existing repo checklists as the procedure:

- Manual QA: `docs/pre-production-qa-checklist.md`
- Backend tests note: `docs/phase1-ordered-tasks.md`

Recommended per-task routine:
- [ ] Flutter: run analysis/tests for touched paths (at minimum `flutter analyze` on touched files)
- [ ] Backend (if touched): run `pytest` for relevant tests
- [ ] Manual smoke for the task’s own `## VALIDATION` section in the task spec MD

