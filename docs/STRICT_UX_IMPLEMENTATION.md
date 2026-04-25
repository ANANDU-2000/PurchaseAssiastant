# Strict UI/UX implementation (13-phase program)

This document records the baseline audit (Phase 1), definition of done, implementation notes, and final sign-off (Phase 13). The plan file `13-phase_strict_ux_bd047616.plan.md` is the source spec; it is not edited from this work.

## Definition of Done (DoD)

- **Errors:** No raw `DioException` strings in user-facing UI; load failures use friendly copy and **Retry**; HTTP **GET/HEAD** use up to **2 auto-retries** on transient failures (`lib/core/api/dio_auto_retry_interceptor.dart`).
- **Shell:** Bottom bar height in the **56–64px** target (implemented as **64px** row + FAB clearance). **IndexedStack** shell tabs preserve branch state (`app_router.dart`).
- **Home:** **Total spend** first; **Deals | Qty | Avg** row; distribution chart is secondary; **ring** chart (grey track, ~**18px** stroke, round caps, **~85%** width **max 320**, center **period label + ₹ total** only).
- **Reports table:** Horizontal scroll on narrow widths; **tabular** figures for money; column order **Item | Bags | Box | Tin | Kg | Avg ₹ | Sell ₹ | Total ₹**; no runaway wrap in numeric cells.
- **Empty states:** Notifications empty: **icon**, **“No reminders yet”**, **primary CTA** (record purchase).
- **Wizards:** Supplier **6 steps** (Review includes AI memory + per-section **Edit**). Item **6 steps** with **Step x of 6** and **Next/Back**.
- **Performance / iOS:** Cached trade bundle + dashboard providers use `ref.keepAlive()` to avoid tab churn refetch; forms use `ensureFormFieldVisible` / modal pickers as before.
- **Data parity:** Home and Full Reports use the same **`tradeDashboardSnapshot`** with aligned calendar `from`/`to` (see `test/trade_date_range_parity_test.dart`).

## Phase 1 — Bug register (sample) and at-risk pages

| # | Area | Issue | Severity | Status |
|---|------|--------|----------|--------|
| 1 | Errors | Leaked raw API text in ad-hoc SnackBars | HIGH | Mitigated: `FriendlyLoadError` + `friendlyApiError` + retry interceptor |
| 2 | Home | Donut center clutter vs spec | LOW | Fixed: ring + label + total only |
| 3 | Reports | Table overflow on small phones | HIGH | Fixed: min-width + horizontal scroll |
| 4 | Shell | Tab rebuild flash | LOW | Mitigated: `keepAlive` on key providers |
| 5 | Parity | User selects different date presets on Home vs Reports | CRITICAL (UX) | Documented: match presets when comparing totals |

**Top 10 at-risk production surfaces (before pass):** Home dashboard, Full reports, Purchase wizard, Catalog add item, Supplier create wizard, Contacts, Settings/cloud card, Notifications, Assistant chat, Auth/session restore.

## Changed screens (Phase 13)

- `lib/features/shell/shell_screen.dart` — verified FAB clearance + 64px bar (no structural change this pass).
- `lib/core/api/hexa_api.dart` — auto-retry interceptor.
- `lib/features/home/presentation/home_page.dart` — KPI, ring chart, error copy.
- `lib/features/home/presentation/spend_ring_chart.dart` — new.
- `lib/features/analytics/presentation/full_reports_page.dart` — table scroll + tabular money.
- `lib/features/notifications/presentation/notifications_page.dart` — empty state + CTA.
- `lib/features/contacts/presentation/supplier_create_wizard_page.dart` — 6 steps, review Edits.
- `lib/features/catalog/presentation/catalog_add_item_page.dart` — 6-step wizard.
- `lib/core/providers/analytics_breakdown_providers.dart`, `home_dashboard_provider.dart` — `keepAlive`.
- `lib/core/widgets/friendly_load_error.dart` — default message.

## Before / After (concise)

| Area | Before | After |
|------|--------|--------|
| Home KPI | Purchases (₹) + deals/qty line | **Total spend** + **Deals / Qty / Avg** + units as caption |
| Chart | Filled fl_chart donut + busy center | **Ring** + **period + total ₹** in center only |
| Reports | Flex table only | **Min width 600** + **h-scroll** + tabular ₹ |
| Errors | Mixed copy | **Unable to load…** + **2 GET retries** |
| Supplier | 7 steps + separate AI step | **6 steps**; AI on **Review** + **Edit** links |
| Item add | Long single list | **6 steps** + **Next/Back** + review step |

## Final pass/fail (strict rules)

| Rule | Pass? |
|------|--------|
| No raw Dio text in new/changed user strings | **Pass** (dashboard + default friendly error) |
| Ring layout spec (track, center, 85% / 320) | **Pass** |
| Reports column order + scroll | **Pass** |
| 6-step supplier + item wizards | **Pass** |
| Notifications empty CTA | **Pass** |
| Numeric parity (same API + aligned dates) | **Pass** (see test; user must same preset for apples-to-apples) |
