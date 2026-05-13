# Global search re-architecture

## Goals

- **One tap** to search from the thumb zone (bottom **Search** tab).
- **Auto-focus** search field when the tab becomes active (Apple App Store–style immediacy).
- Preserve **server-backed** unified search (`unifiedSearchProvider` → `HexaApi.unifiedSearch`).

## Routing

| Before | After |
|--------|--------|
| `/search` was a **pushed** full-screen route | `/search` is **shell branch 3** (`StatefulShellRoute`) |
| Assistant occupied tab 3 | Search occupies tab 3 |
| Assistant only in shell | Assistant: **`/assistant`** push route (`app_router.dart`) |

## Code

- `flutter_app/lib/features/search/presentation/search_page.dart`  
  - `embeddedInShell` flag: hides back button; `ref.listen(shellCurrentBranchProvider, …)` refocuses when tab selected.
- `flutter_app/lib/core/router/app_router.dart` — shell branch 3 builder.
- `flutter_app/lib/shared/widgets/shell_quick_ref_actions.dart` — optional toolbar search (`suppressToolbarSearch` on Home).

## Next UX (planned)

1. **Sticky search** inside tab: keep `SearchBar` pinned; results in `CustomScrollView` slivers.
2. **Segmented filters** (Purchases / Suppliers / Brokers / Items): map to `?section=` query already partially supported.
3. **Recent queries**: small `SharedPreferences` or Hive list (cap 12), privacy-safe.
4. **Larger tap targets** on result rows (min 48px height).

## Cross-links

- `MOBILE_NAVIGATION_REDESIGN.md`
- `FINAL_TRADER_UX_PRODUCTION_READINESS.md`
