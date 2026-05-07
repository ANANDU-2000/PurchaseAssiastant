# Purchase History rebuild

## Goals

Dense wholesale-trader workflow: above-the-fold KPIs, compact search + filters, correct pack summaries, latest-first ordering, and automatic refresh after mutations.

## Implemented (Flutter)

- **Header**: Title + current calendar month subtitle; **New purchase** in app bar.
- **Metric pills** (horizontal scroll): Due soon count, month purchase count, month amount (compact ₹/L/Cr), overdue count (tap Due / Overdue to filter).
- **Month strip**: Total spend + `bags • boxes • tins • kg` (kg from bag lines + loose kg only; never from box/tin).
- **Search row**: ~82% / ~18% — search field + filters sheet (tune icon).
- **Quick chips**: All, Due, Paid, Draft (scrollable).
- **Filter sheet**: Sort (latest first), payment shortcuts, date range (API), package type, supplier/broker contains, clear advanced.
- **Cards**: Supplier, item headline, pack summary line, `PUR-ID • date`, amount + compact status chip.
- **List fetch**: Up to **4000** rows via existing API paging (`kTradePurchasesHistoryFetchLimit`).
- **Alerts / month KPIs**: Derived from **`tradePurchasesForAlertsParsedProvider`** so chip counts stay correct while the tab filter is Draft/Paid/etc.
- **Error UX**: Softer `FriendlyLoadError` copy + retry.
- **PDF share**: Calls `invalidatePurchaseWorkspace` after successful share.

## Related docs

- `62_PURCHASE_CARD_STANDARD.md` — row layout.
- `63`–`70` — search, filters, sync, status, packages, performance, share metadata, QA.
