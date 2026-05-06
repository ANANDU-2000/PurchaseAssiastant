# 22 — Agent Rules (Cursor AI Operating Protocol)

## Hard rules

- Work **one task at a time**.
- After every task:
  - update `docs/20_PROGRESS_TRACKER.md`
  - run tests relevant to the layer touched
  - ensure no regressions
- Never auto-save AI scan output; preview + confirm required.
- Never invent purchase rates, averages, or supplier/broker matches.
- Packaging system is strict: `KG|BAG|BOX|TIN|PCS` only.

## Required task flow

For every feature:

spec → db → backend → calculations → validation → UI → responsive testing → report testing → PDF testing → offline testing → duplicate testing → edge-case testing → production validation → mark complete

## Documentation policy

Architecture decisions must be recorded in the relevant doc file and referenced in code changes.

