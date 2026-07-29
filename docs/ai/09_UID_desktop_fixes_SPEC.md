# Desktop UI Fixes — Specs

Source: screenshots of the live app at `purchase-assiastant.vercel.app` (dashboard, stock item
modal, blank `/stock` reload). IDs below track against the diff — check a box only when you can
point to the exact lines that satisfy it.

---

### UID-001: `/stock` must never render fully blank on direct load/reload
- [x] A hard reload or direct navigation to `/stock` (or any deep link) shall always show either
  the loading skeleton, the signed-out/login screen, or the real content — never an empty page
  with no header, nav, or spinner.
- [x] If session restore is still in flight when the boot splash is removed, the route shall show a
  loading state until the session resolves, not nothing.
- [x] If session restore fails or throws, the route shall show a user-facing error (per the
  existing `FriendlyLoadError` / `HexaLayoutErrorWidget` pattern), not a blank page.

*Proof:* [`main.dart`](../../flutter_app/lib/main.dart) — HTML splash is released only after bootstrap spinner/error/HexaApp is in the tree (`_scheduleBootOverlayRelease`); no first-frame empty wipe. Stock still uses `ListSkeleton` / auth `FriendlyLoadError`. [`remove_boot_overlay_web.dart`](../../flutter_app/lib/core/platform/remove_boot_overlay_web.dart) docs updated.

### UID-002: Low-stock count must be consistent across the dashboard
- [x] The "Low stock" quick-filter chip count and the "Low stock" metric card count shall either
  read from the same source and always match, or be relabeled so it's clear they measure different
  things (e.g. "Low stock (filtered to this period)" vs "Low stock (all time)").
- [x] Same check for "Out of stock" chip vs any other out-of-stock figure shown elsewhere on the
  dashboard.

*Proof:* [`home_owner_dashboard_body.dart`](../../flutter_app/lib/features/home/presentation/widgets/home_owner_dashboard_body.dart) — chip **Below reorder · $low**; KPI **Need attention** = `low+out` with subtitle `Below reorder $low · Out $out`; out remains its own chip.

### UID-003: Pending badge in stock list rows must be legible
- [x] The truck/pending badge (e.g. currently rendering as "52 38d") shall visually separate the
  quantity and the day-count — spacing, a divider, or explicit unit text (e.g. "52 BAG · 38d
  pending") — so neither number reads as a single ambiguous figure.
- [x] The badge shall use the same pattern across every row (currently consistent, keep it that
  way — don't let this fix introduce a second one-off variant).

*Proof:* [`stock_row_metrics.dart`](../../flutter_app/lib/features/stock/presentation/widgets/stock_row_metrics.dart) `inlineDeliveryCue` — `HexaDsSpace.xs` + middle-dot between qty and days.

### UID-004: Item action modal must not visually collide with page content behind it
- [x] The modal (Update physical stock / Update system stock / Add purchase quantity / View item
  activity) shall not overlap the "New purchase / Set reorder / Full detail" action buttons in the
  right-hand detail panel on desktop widths.
- [x] Either add a scrim/backdrop behind the modal so the covered buttons read as clearly
  inactive, or reposition/resize the modal so it doesn't sit on top of live interactive controls.

*Proof:* [`stock_row_actions.dart`](../../flutter_app/lib/features/stock/presentation/widgets/stock_row_actions.dart) + [`hexa_responsive.dart`](../../flutter_app/lib/core/design_system/hexa_responsive.dart) — `desktopAlignment: Alignment.centerLeft`, right inset leaves detail pane, `barrierColor: Colors.black54`.

### UID-005: Modal subtitle must match the value it's next to
- [x] The modal subtitle currently reading "Stock in hand · 100" shall either match the Physical
  count shown directly below it (105) or be relabeled to make clear which figure it's summarizing
  (System vs Physical) — right now it silently repeats the System number under a generic label,
  which reads as a mismatch even if it's technically correct.

*Proof:* [`stock_row_actions.dart`](../../flutter_app/lib/features/stock/presentation/widgets/stock_row_actions.dart) + [`low_stock_item_detail_sheet.dart`](../../flutter_app/lib/features/stock/presentation/widgets/low_stock_item_detail_sheet.dart) — subtitle **System stock · N**.

---

## Why these exist

- **UID-001** is the one that actually loses users mid-session (hard refresh = blank page = looks
  like the app crashed). Highest priority — this is a trust/reliability issue, not cosmetic.
- **UID-002 / UID-005** are "the numbers don't agree with each other" issues — the fastest way to
  make an ERP tool feel untrustworthy, even when every individual number is technically correct.
- **UID-003 / UID-004** are straightforward density/z-index issues, lower risk but still visible on
  every stock-list interaction.
