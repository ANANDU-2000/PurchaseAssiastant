# BUGS — Purchase Assistant

_File severity, reproduction, affected surfaces, and status. Link PRs/commits when fixed._

## Template

```text
ID: BUG-###
Severity: P0|P1|P2|P3
Title:
Repro:
Expected:
Actual:
Affected: (screens / API / reports)
Status: open | investigating | fixed | wontfix
Notes:
```

## Known / reported (from product rules — verify before closing)

| ID | Severity | Title | Status |
|----|----------|--------|--------|
| BUG-001 | P0 | Wrong item match (e.g. wholesale sugar line → unrelated retail SKU) | **partial** — backend pack kg + unit-channel gate demotes bad auto-matches; aliases/fuzzy ranking still TBD |
| BUG-002 | P0 | Unit/pack mismatch destroys kg/bags/totals | open |
| BUG-003 | P1 | Dashboard/reports/charts disagree or flip to empty | open |
| BUG-004 | P1 | Purchase deleted in UI but data/cache still surfaces | open |
| BUG-005 | P2 | Scan extraction misses freight/bilty/delivered/commission fields | open |
| BUG-006 | P2 | Item search typing short prefix returns no suggestions | open |

_Add rows as you confirm reproducers in this codebase._
