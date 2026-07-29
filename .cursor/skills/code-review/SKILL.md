---
name: code-review
description: "Repo-agnostic code review pass focused on catching AI-agent slop: incomplete features, silently-dropped scope, cross-file logic bugs, and persistence bugs. Trigger with /codereview or when the user asks to review/verify a Cursor agent's changes before committing."
version: 1.0.0
---

# Code Review — anti-slop pass

Not a style/lint pass — catch claimed-done-but-isn't, scope creep, and cross-file bugs.

## Before anything else: does the diff match the spec?

If a spec exists under `specs/` (see `debugerseniorcode/06_SPEC_TEMPLATE.md`), go through it ID by ID against the **actual** `git diff`. A requirement is only done if you can point to the lines that satisfy it. Do not trust the agent summary.

Also read root `AGENTS.md` lessons — regressions of those patterns are blocking.

## Core checks (in order)

1. **Every stated requirement landed** in code, not the changelog.
2. **Persistence** — writes actually reach API/DB/file and commit; invalidate the right providers.
3. **Cross-file data flow** — trace 1–2 levels into callees.
4. **Business-logic correctness** for money/qty — re-derive one concrete example.
5. **Scope** — flag files outside the stated task.
6. **Error handling** — failure path shows friendly UI, not silent catch.
7. **No duplicate business logic** — reuse existing helpers/providers.
8. **State** — Riverpod/`ref.invalidate` patterns match the rest of the app.

## What NOT to flag

Minor style, nice-to-haves, praise for fine code.

## Output format

For each issue: wrong / why it matters / specific fix. End with:
- **Ready to commit** — or —
- **Blocking issues found** — ranked by production impact.

When a real bug class is caught, append a lesson to `AGENTS.md`.
