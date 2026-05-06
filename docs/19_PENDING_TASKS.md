# 19 — Pending Tasks (Master Rebuild)

## Current priority order

1. **Finish docs 00–22** (this set)
2. **Refactor unit system** to `KG|BAG|BOX|TIN|PCS` across backend + Flutter
3. **Rebuild calculations** to be package-aware and deterministic
4. **Rebuild purchase preview UI** to table-first + no overflow
5. **Fix reports aggregation** for package types
6. **Fix PDF template** rules
7. **Scanner v2 endpoints** and confirm-save flow
8. **Offline queue + sync**

## Current work-in-progress (now)

- Unit refactor:
  - normalize legacy `sack` → canonical `bag` (display + totals)
  - standardize `pc/pcs` → `piece`
  - remove `sack` from all unit dropdowns and labels
  - ensure BOX/TIN do not show kg totals in default mode (done)
  - dynamic form engine: hide BOX/TIN kg/weight/item fields in default wholesale mode (done)
- Next:
  - deterministic calculation engine SSOT cleanup (eliminate duplicate math paths)

## Notes

Work one task at a time; after each task update `20_PROGRESS_TRACKER.md`.