## MASTER TASK LIST (CONTROL CENTER)

Read first: `context/00_AGENT_RULES.md`

This file defines the **only allowed build order**.

---

## RULES (NON-NEGOTIABLE)

- **Pick ONLY ONE task at a time**: always choose the **first unchecked** task in the list below.
- **Finish FULLY before next**: implement *everything* inside that task spec file (all ❌ and ⚠️ items).
- **No skipping tasks**: do not jump ahead, do not reorder.
- **Update progress after each action**: after each meaningful change (planning, coding, fixing, validating), update `context/99_PROGRESS_TRACKER.md`.
- **Quality gate required**: before marking a task complete, run validation using `context/98_VALIDATION.md`.
- **If any validation fails**: do not mark the task complete; fix immediately and re-validate.

---

## TASK ORDER (DO NOT CHANGE)

- [01_PURCHASE_WIZARD.md](./01_PURCHASE_WIZARD.md)
- [02_ITEM_ENTRY.md](./02_ITEM_ENTRY.md)
- [03_TERMS_STEP.md](./03_TERMS_STEP.md)
- [04_PURCHASE_HISTORY.md](./04_PURCHASE_HISTORY.md)
- [05_PURCHASE_DETAIL.md](./05_PURCHASE_DETAIL.md)
- [06_REPORTS.md](./06_REPORTS.md)
- [07_DRAFT_AUTOSAVE.md](./07_DRAFT_AUTOSAVE.md)
- [08_PDF_PRINT.md](./08_PDF_PRINT.md)
- [09_SETTINGS_WHATSAPP.md](./09_SETTINGS_WHATSAPP.md)
- [10_PERFORMANCE.md](./10_PERFORMANCE.md)
- [11_BROKER_IMAGES.md](./11_BROKER_IMAGES.md)
- [12_SUPPLIER_DETAIL.md](./12_SUPPLIER_DETAIL.md)
- [13_REPO_HYGIENE.md](./13_REPO_HYGIENE.md)
- [14_SMOKE_TESTS.md](./14_SMOKE_TESTS.md)

---

## CURRENT TASK

→ `context/14_SMOKE_TESTS.md` (ALL TASKS COMPLETE)

---

## COMPLETED

→ `context/01_PURCHASE_WIZARD.md`, `context/02_ITEM_ENTRY.md`, `context/03_TERMS_STEP.md`, `context/04_PURCHASE_HISTORY.md`, `context/05_PURCHASE_DETAIL.md`, `context/06_REPORTS.md`, `context/07_DRAFT_AUTOSAVE.md`, `context/08_PDF_PRINT.md`, `context/09_SETTINGS_WHATSAPP.md`, `context/10_PERFORMANCE.md`, `context/11_BROKER_IMAGES.md`, `context/12_SUPPLIER_DETAIL.md`, `context/13_REPO_HYGIENE.md`, `context/14_SMOKE_TESTS.md`

---

## EXECUTION PROMPT (COPY/PASTE FOR EACH SESSION)

SYSTEM PROMPT — TASK EXECUTION ENGINE

You are a strict development agent.

RULES:

Read `context/00_MASTER_TASKS.md`
Pick ONLY the first incomplete task
Set it as CURRENT TASK
Update `context/99_PROGRESS_TRACKER.md`
Open that task file
Complete ALL requirements inside it
Do NOT skip anything
After implementation:
Run validation using `context/98_VALIDATION.md`
If ANY issue:
Fix before proceeding
If ALL PASS:
Mark task as COMPLETE in MASTER
Update PROGRESS_TRACKER
Move to next task
After EACH action:
Update PROGRESS_TRACKER.md
NEVER:
skip tasks
leave partial work
jump files

GOAL:
Complete full system step-by-step with zero bugs.