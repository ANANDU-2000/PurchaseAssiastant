# Reports provider stability

## Goals

- No “infinite spinner” when Hive or network has usable data.  
- Clear separation: **loading**, **error / degraded**, **empty**, **data**.  
- Debounced or deduplicated fetches when period or shell tab changes.  
- No duplicate inflight requests for the same business + date range key.

## Key providers

**File:** [`flutter_app/lib/core/providers/reports_provider.dart`](../../flutter_app/lib/core/providers/reports_provider.dart)

| Provider | Role |
|----------|------|
| `reportsPurchasesPayloadProvider` | `FutureProvider.autoDispose` — primary payload for the analytics date range; integrates session, `shellCurrentBranchProvider`, Hive cache; **silent refresh** when not on Reports tab; `keepAlive()` to reduce thrash |
| `_reportsPurchasesInflight` | `putIfAbsent` per key so concurrent watches share one future |
| `_loadReportsPurchases` | Retry loop with backoff; throws after exhaustion |
| `reportsPurchasesHiveCacheProvider` | Offline / last-good cache |
| `reportsPurchasesMergedProvider` | Merges async state with cache so UI is not falsely empty while reloading |
| `fetchReportsPurchasesLiveForAnalytics` | Shared live fetch + auth handling (`DioException` 401/403 → logout attempt) + fallback to cache with `liveFetchError` message |

## UI layer

**File:** [`flutter_app/lib/features/reports/presentation/reports_page.dart`](../../flutter_app/lib/features/reports/presentation/reports_page.dart)

- Watches `reportsPurchasesPayloadProvider` and `reportsPurchasesMergedProvider`.  
- Uses `hasError` / error cards / retry flows (invalidate payload) so users are not stuck on a spinner with contradictory copy.  
- Overview chart section handles load-failed states (`reports_overview_chart_section.dart` in same feature folder).

## Operational notes

- **Branch awareness:** When `shellCurrentBranchProvider != ShellBranch.reports`, behavior prefers cached Hive data and throttled background refresh—documented in-code to support IndexedStack mounting Reports off-screen.  
- **Invalidation:** Settings and home flows may call `ref.invalidate(reportsPurchasesPayloadProvider)` when business or range must refresh.

## Verification

1. Slow network: switch **Today → Week → Month**; expect at most brief loading, then data or explicit error + **Retry**.  
2. Offline after successful cache: expect merged list or empty with clear messaging, not perpetual loading.  
3. 401 from API: session handling path should not spin forever.

## Related

- [CRITICAL_RUNTIME_FAILURES.md](CRITICAL_RUNTIME_FAILURES.md)  
- [PURCHASE_HISTORY_RENDER_FIX.md](PURCHASE_HISTORY_RENDER_FIX.md) (different provider: purchase list vs reports aggregate)
