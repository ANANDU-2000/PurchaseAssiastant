# Navigation and search (Phase 1 shipped, Phase 2 roadmap)

## Phase 1 — current shell

**File:** [`flutter_app/lib/features/shell/shell_screen.dart`](../../flutter_app/lib/features/shell/shell_screen.dart)

- Bottom navigation pattern documents **Home | Reports | History | Search** plus add-purchase affordance (see in-file comments / implementation).  
- **Search** is a first-class tab (`shell_branch_provider.dart` notes global search replacing former Assistant **tab**; Assistant may still be reachable from toolbar — [`shell_quick_ref_actions.dart`](../../flutter_app/lib/shared/widgets/shell_quick_ref_actions.dart)).

## Direct navigation to trade items

**Files:**

- [`home_breakdown_list_page.dart`](../../flutter_app/lib/features/home/presentation/home_breakdown_list_page.dart) — uses `go_router` + helpers such as [`open_trade_item_from_report.dart`](../../flutter_app/lib/core/navigation/open_trade_item_from_report.dart) for report-driven jumps; category/type navigation uses explicit paths like `/catalog/category/:cid/type/:tid` when IDs exist (avoid generic multi-hop where unnecessary).  
- [`home_page.dart`](../../flutter_app/lib/features/home/presentation/home_page.dart) — invalidates reports-related providers when dashboard data must refresh.

Prefer **`context.push`** / typed helpers for item detail when the goal is “open this item ledger now” without redundant intermediate pages.

## Item history refresh

**File:** [`item_history_page.dart`](../../flutter_app/lib/features/item/presentation/item_history_page.dart)

- Uses **`itemHistoryLinesProvider(catalogItemId)`** (family keyed by item id — **not** `itemTradeHistoryProvider`).  
- Post-frame `ref.invalidate(itemHistoryLinesProvider(widget.catalogItemId))` on open so stale empty states are less likely.

## Phase 2 roadmap (not in Phase 1 scope)

Per product request **16–20** deferral:

1. **App Store–style global search** — sticky search, recent queries, larger hit targets, segmented chips without relying on outer scroll.  
2. **FAB ergonomics** — WhatsApp-style thumb reach for “Add purchase” if moved from current placement.  
3. **Home → item** — further reduce any remaining multi-hop catalog navigation where IDs are known upfront.  
4. **Deep links** — preserve `goBranch` / shell state when returning from error boundary “Go to Home”.

When implementing Phase 2, update this doc and [`FINAL_PRODUCTION_UX_READINESS.md`](FINAL_PRODUCTION_UX_READINESS.md).
