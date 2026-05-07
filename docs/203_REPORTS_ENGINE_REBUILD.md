# 203 — REPORTS_ENGINE_REBUILD

## 1. PURPOSE

Make the Reports page a fast, reliable “truth view” for wholesale trading:

- totals match DB
- filters match Home/History period
- lists are dense and actionable
- refresh is realtime without full-app refetch storms

## 2. PROBLEM STATEMENT

Traders open Reports repeatedly during the day. Any “loading forever”, false offline banners, or inconsistent totals destroys trust.

## 3. CURRENT FAILURE

- False “Offline/server unreachable” banner could appear while live refresh was still loading (cache shown).
- Too many refetches can happen on refresh/tab switching (perceived as slow).
- “View more” discoverability and list density was weak.

## 4. TARGET BEHAVIOR

- Reports loads in < 1s when cached data exists; < 3–8s cold.
- When refreshing, keep existing data visible and show “Refreshing…” (not offline).
- Lists show many rows on screen and expose full list with count.
- Totals must equal DB totals for the selected range.

## 5. UI RULES

- **No blank screen** while refreshing: keep cached list visible.
- **Top period** always visible and clear (Today/Week/Month/Year/Custom).
- **Tabs**: Overview / Items / Suppliers / Brokers.
- **Row density**:
  - compact typography and padding
  - show 8–12 rows on screen
- **CTA**:
  - “View full list (N)” instead of vague “View more”
- **Refresh UX**:
  - if loading and cached exists: “Refreshing live data…”
  - if live fetch actually failed: “Showing saved copy” + Retry

## 6. BACKEND RULES

- List endpoint must be stable and fast:
  - `GET /v1/me/trade-purchases?purchase_from=YYYY-MM-DD&purchase_to=YYYY-MM-DD&limit=...`
- Server must not require many small calls for one reports view.

## 7. DATABASE RULES

- Use indexed filters on `purchase_date` and `business_id`.
- Avoid full table scans for common ranges (Today/Week/Month).

## 8. API CONTRACTS

### Data source (current)

Reports uses the same `/trade-purchases` list as History and then aggregates client-side.

### Client payload provider

- Flutter: `reportsPurchasesPayloadProvider` in `flutter_app/lib/core/providers/reports_provider.dart`
  - live fetch with per-page timeout (10s)
  - hive cache fallback keyed by `(business_id, from, to)`

### Refresh contract

- pull-to-refresh invalidates only `reportsPurchasesPayloadProvider` (no global `invalidatePurchaseWorkspace`)

## 9. VALIDATION RULES

- Aggregation must dedupe purchase ids.
- If API date filter returns empty but summary indicates deals exist, run unfiltered fallback and filter locally (timezone edge mitigation).

## 10. ERROR HANDLING

- Never show raw Dio exceptions.
- User message:
  - “Could not refresh live data. <short reason>”
  - show Retry button

## 11. LOADING STATES

- **Loading + cached exists**: show cached + small “Refreshing…” banner.
- **Loading + no data**: skeleton/indicator.
- **Error + cached exists**: show cached + “saved copy” banner.
- **Error + no cached**: empty card + Retry.

## 12. PERFORMANCE TARGETS

- p50: < 1s to render with cached data
- p95: < 8s cold (Render cold start may dominate)
- Avoid N+1 refetch storms on tab changes

## 13. CACHE RULES

- Cache reports purchases per range in OfflineStore (Hive/Prefs-backed).
- Cache invalidated implicitly via short TTL or after purchase write events.

## 14. REALTIME SYNC RULES

- After purchase create/update/delete/paid:
  - invalidate `reportsPurchasesPayloadProvider`
  - invalidate trade purchase list caches (History)

## 15. EDGE CASES

- Very large ranges (Year) → ensure list caps and full-screen list works.
- Weak network: timeouts should fall back to cached data without freezing.

## 16. FAILURE RECOVERY

- Automatic retry with backoff at provider level (limited attempts).
- Manual Retry button always available when not loading.

## 17. SECURITY RULES

- Membership enforcement on all report endpoints.
- No cross-tenant leakage in cached keys.

## 18. TEST CASES

- Cached data present + slow network → shows “Refreshing…”
- Live fetch fails → shows “saved copy” banner + Retry
- “View full list (N)” opens full-screen list
- Totals match DB for same range

## 19. ACCEPTANCE CHECKLIST

- [ ] No false offline banner while loading
- [ ] Reports does not trigger full-app refetch storm on retry/tab switch
- [ ] Dense list rows + “View full list (N)”
- [ ] Totals correct across periods

## 20. FINAL EXPECTED OUTPUT

A Reports page that is fast, stable under weak networks, and trusted: totals correct, refresh visible, and no endless spinners.

