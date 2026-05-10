# Remaining risks

1. **Scanner matching:** Malayalam / manglish and duplicate SKU confusion still depend on catalog quality and matcher thresholds; learning tables are not yet consumed in `matcher.py`.
2. **Historical rows:** Old purchases without `rate_context` rely on Flutter/backend fallbacks; edge cases may still mis-label rates in niche units.
3. **Performance:** No measured SLIs yet; large widgets (`purchase_item_entry_sheet`) still use many `setState` calls.
4. **Soft delete:** Not every read path has been grep-verified for `deleted_at` / cancelled status.
5. **PDF recompute:** `buildProfessionalPurchaseInvoiceDoc` compares `computeTradeTotals` to `total_amount`; edge cases with partial line payloads could still show mismatch note.
