# Progress log

| Date (UTC) | Summary |
|------------|---------|
| 2026-05-14 | Flutter web: `app.dart` API degraded banner — remove `IconButton` `tooltip` (RawTooltip needs Overlay under `Navigator`); fixes “No Overlay” + cascade errors when banner shows. |
| 2026-05-12 | Flutter: purchase History KPI no longer uses alerts fallback during main-list load (avoids “33 purch + blank list” on web); `/purchase` `didChangeDependencies` syncs shell branch + one-shot `invalidate(tradePurchasesListProvider)` when returning to History; prior: broker `_step2`, shell `double` pad, catalog edit sheet focus, fullscreen search flag in `trade_purchases_provider`. |
| 2026-05-12 | Flutter: broker wizard `_step2` search field focus + scroll padding; shell bottom bar `bottomPad` typed as `double` (fix `math.max` `num`); catalog edit-item sheet extracted to `_EditCatalogItemDefaultsSheet` with focus nodes + `bindFocusNodeScrollIntoView` + `formFieldScrollPaddingForContext`; save returns `{'ok','unit'}` map. |
| 2026-05-14 | Flutter: purchase history KPI aligned with list provider; filter-empty UX; shell branch guard on Purchase Home; purchase detail 15s timeout + GoRouter `extra` seed; error boundary non-fatal in all modes; focus-scroll on wizard Terms / add-item / supplier name; shell bottom extra home-indicator padding; reports stall banner 1.5s; ten `docs/production-readiness/*.md` runbooks; `keyboard_lifted_footer.dart`; `CHANGELOG.md` updated. |
