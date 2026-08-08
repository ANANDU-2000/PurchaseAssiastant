# Diagnostic Report — Slowness / Repeated Refresh

Date: 2026-07-29  
Methods: Code audit of scoped files + browser Network/`performance` on `https://purchase-assiastant.vercel.app` (session already present → `/home`, then hard nav to `/stock`).

Visibility/alt-tab could not be forced via CDP (`document.hidden` non-configurable). Flutter a11y tree is thin (canvas), so SPA tab clicks were not reliably automatable.

---

## Scenario 2 — Rapid alt-tab / overlapping refresh

**Verdict: CONFIRMED (code race). Network alt-tab not observable in automation.**

Evidence:
- [`app_foreground_listener.dart`](../../flutter_app/lib/core/platform/app_foreground_listener.dart): no in-flight guard; `await ApiWarmupService.pingHealth(...)` runs **before** 2s/30s stamp updates.
- Two overlapping `_onReturnedToForeground` calls can both hit `/health/live` + `/health/ready` while the first is still awaiting.

**Task A:** APPLY

---

## Scenario 3 — Cold start / long wake without feedback

**Verdict: PARTIAL — bootstrap has feedback; foreground resume is silent.**

Browser (warm host this run):
- Initial HTML splash showed “Connecting to server…” then app mounted.
- `/health/live` ~76–100ms; `/health/ready` ~160–350ms (API already warm — not a long cold wait this session).
- Bootstrap path in `main.dart` already uses `onSlow` → `apiDegradedProvider` (“Waking server…”).

Code gap:
- Foreground `pingHealth` in `AppForegroundListener` passes **no** `onSlow` / clear — a cold resume can await health with no banner.

**Hosting note:** Long wakes remain a Render (or similar) free-tier spin-down issue; app should make the wait legible, not “fix” infra.

**Task B:** APPLY (foreground `onSlow` → degraded banner)

---

## Scenario 4 — Rapid navigation / unrelated per-route refetch

**Verdict: NOT RELATED for this pass (no named speculative providers).**

- Hard navigation to `/stock` caused a **full app reload** (bootstrap + shell-bundle + catalogs again) — expected for full document load, not IndexedStack tab return.
- Could not automate in-shell tab switches on Flutter web a11y.
- Stock already has `stockListLastFetchedAtProvider` + `kStockListCacheTtl`; shell tab listener already TTL-gates stock.

**Task C:** SKIP — no Scenario-4-named route providers.

---

## Scenario 5 — Multiple tabs / duplicate backend hits

**Verdict: KNOWN LIMITATION (code). Cross-tab Network not run.**

- Throttle stamps are **instance fields** on each tab’s `AppForegroundListener` → per-tab-independent, not shared/broken across tabs.
- No `BroadcastChannel` / cross-tab lock.

**Task D:** NOTE ONLY — no cross-tab lock this pass.

---

## Step 3 — `reloadHexaApp`

**Call sites: 1** — [`hexa_layout_error_widget.dart`](../../flutter_app/lib/core/platform/hexa_layout_error_widget.dart) ErrorWidget “Reload”.

**Task E:** KEEP + short intentional-use comment. Do not delete.  
Throttle compares use live `DateTime.now()` after ping (not a stale closed-over clock); placement after `await pingHealth` is why Task A is required.

---

## Apply / skip summary

| Task | Decision |
|------|----------|
| A | Apply |
| B | Apply |
| C | Skip |
| D | Note only |
| E | Apply (comment + verify) |
