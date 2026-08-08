# Cursor Prompt — UID-006, UID-007, UID-008

Implements `docs/ai/12_UID_006_008_SPEC.md`.

## Scope lock

- `features/stock/presentation/quick_stock_action_sheet.dart`
- `features/stock/presentation/stock_undo_snackbar.dart` (if System snackbar lives there)
- `features/stock/stock_list_row_patch.dart`
- `features/purchase/presentation/wizard/purchase_fast_items_step.dart`
- `features/purchase/presentation/wizard/purchase_party_step.dart`
- `features/purchase/presentation/wizard/purchase_review_tally_step.dart`
- Plus `docs/ai/12_UID_006_008_SPEC.md` / `TASKS.md` for checklist only.

## Tasks

1. **UID-006** — System success must be floating + clear "System stock updated…" tone; keep Undo.
2. **UID-007** — Verify PATCH fields vs `stockListPatchFromStockDetail`; add `system_qty` alias;
   keep empty-patch system fallback; report mismatch vs safety-net.
3. **UID-008** — Adopt `AppFormRow` for short pairs (pattern: `purchase_terms_only_step.dart`).

## Finish

- `git diff --stat` against scoped files only.
- Check off UID boxes only when proven in the diff.
- For UID-007: state field-mismatch finding explicitly.
