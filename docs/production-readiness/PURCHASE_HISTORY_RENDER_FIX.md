# Purchase history list render and filters

## Data sources (correct names)

Do **not** confuse with older audit nicknames:

- **`tradePurchasesListProvider`** — paginated / loaded purchase list for the Purchase home experience ([`trade_purchases_provider.dart`](../../flutter_app/lib/core/providers/trade_purchases_provider.dart)).  
- **`purchaseHistoryValueSortProvider`** — `StateProvider<String?>` for value sort mode (`null` = default date ordering, `'high'` / `'low'` for amount sort). Intentionally **not** cleared by generic cache invalidation where sort is user preference.

## UI file

**[`purchase_home_page.dart`](../../flutter_app/lib/features/purchase/presentation/purchase_home_page.dart)**

- KPI strip and filters at top; list body must stay in a **bounded** vertical flex (`Expanded` / sliver) so `ListView` does not get unbounded height.  
- Multiple `ref.watch` / `ref.read` paths call `tradePurchasesListProvider` / `.notifier.loadMore()` for pagination.  
- Delivery / aging presentation: overdue undelivered uses visible warning affordances (e.g. `timer_off_rounded` chip where applicable); sort chips wired to `purchaseHistoryValueSortProvider`.  
- PDF share: `await sharePurchasePdf(...)` then SnackBar + Retry if `!ok`.

## Empty list with visible KPIs

If reproduced again, check in order:

1. **Date / status filters** — active tab (All / Due / Paid / Draft / Awaiting) may exclude all rows.  
2. **Parsed vs raw** — `tradePurchasesParsedRowsProvider` tracks list without blocking on `.future`; ensure not filtering everything by mistake after a provider change.  
3. **Layout** — `ListView` inside `SingleChildScrollView` without bounded height → zero visible rows; restore `Expanded` or `CustomScrollView` + slivers.

## Verification

- Seed data with mixed statuses; flip each filter; counts and cards should align.  
- Toggle **₹ High→Low** / **₹ Low→High** / default; order should match totals.  
- Pull to refresh / invalidate after new purchase from wizard.

## Related

- [REPORTS_PROVIDER_STABILITY.md](REPORTS_PROVIDER_STABILITY.md)  
- [PDF_EXPORT_HARDENING.md](PDF_EXPORT_HARDENING.md)
