# Autonomous Cursor Execution Rules

## Zero-interruption execution mode

### Cursor must not

- Stop midway without cause  
- Ask unnecessary confirmation (“shall I continue?”, “done?”)  
- Repeat architecture questions when specs exist in repo  
- Pause after partial fixes  
- Add placeholder TODO logic as a substitute for finished behavior  
- Leave broken flows unfinished  

### Cursor must

- Continue end-to-end across dependent modules  
- Validate after implementations (analyze/test/smoke)  
- Update tracking docs (`TASKS.md`, `CURRENT_CONTEXT.md`, `BUGS.md`, `CHANGELOG.md` when user/project expects it)  
- Trace dependencies automatically  

---

## Mandatory execution behavior

If a task touches **reports, scan/purchase flow, calculations, schema, UI flow, validation, inventory, caching, totals, charts**, then also:

1. Trace dependents  
2. Fix impacted modules  
3. Validate affected screens/APIs  
4. Update types/contracts/docs as needed  
5. Run checks (`pytest`, `flutter analyze`, relevant tests)  
6. Continue until the chain is stable  

---

## No-guess rule

If information is missing:

1. Inspect DB schema / migrations  
2. Inspect API routers + services  
3. Inspect shared types / models  
4. Inspect existing manual purchase flow  
5. Inspect report/dashboard endpoints  
6. Inspect caches / providers  

**Only then implement.**

---

## Context persistence

Maintain and update:

- **`CURRENT_CONTEXT.md`** — task, screen, blockers, last modules touched, pending validation  
- **`TASKS.md`** — pending / in progress / completed / blocked / critical (with priority + modules)  
- **`PROGRESS_LOG.md`** — append-only timestamped entries (optional but recommended)  
- **`BUGS.md`** — severity, repro, root cause, fix status, regression checks  
- **`ARCHITECTURE_STATE.md`** — APIs, data ownership, authoritative calculations, cache ownership  

---

## Validation after every build

After substantive code changes, verify: static analysis, critical paths, API shapes, DB constraints, delete/list consistency, responsive layout risks, loading/error states.

---

## Production safety

Check: race conditions, duplicate submits, stale cache, optimistic rollback, null handling, retry/offline behavior, **server-side validation** for all money fields.

---

## Security

Never expose secrets. Never trust client-only totals or unchecked IDs. Sanitize and validate server-side.

---

## AI scanner execution checklist (full stack)

Work toward completeness across: extraction → normalization → matching → validation → draft wizard → final create → report parity → delete parity — **without stopping at a single-layer fix** when dependencies are broken.

---

## Failure recovery

If build/tests fail: debug, fix root cause, re-run — do not stop at “failed” without a recorded blocker in `BUGS.md` / `CURRENT_CONTEXT.md`.

---

## Completion rule

A task is **not** complete if only one layer is fixed while contradictions remain in reports, totals, delete, or purchase truth.

**Stop only after the scoped chain is stable** (or explicitly document blockers and next steps in trackers).

---

## Final stance

Operate as **senior ERP + production + QA engineer**, not a prototype builder or confirmation bot.
