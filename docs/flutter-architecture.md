# Flutter App Architecture — HEXA Purchase Assistant

## Goals

- **<16ms** frame budget on core screens; lazy lists for history.
- **Offline-friendly:** queue writes when offline; sync with conflict rules (server wins + notify user).
- **Minimal taps:** quick entry as default path; preview before save everywhere.

## Recommended Layout (`flutter_app/lib/`)

```
lib/
  main.dart
  app.dart                 # MaterialApp.router, theme
  core/
    router/                # go_router or auto_route
    theme/                 # ThemeData, extensions
    network/               # Dio + interceptors, base URL from env/flavor
    auth/                  # token storage (flutter_secure_storage), refresh
    config/                # flavors: dev, staging, prod
  features/
    home/
    entries/
    analytics/
    contacts/
    settings/
  shared/
    widgets/               # PIP card, charts wrappers, bottom sheets
    models/                # DTOs mirroring API
    services/              # thin API clients
```

## Navigation

Use **bottom navigation** with 5 branches:


| Index | Route        | Feature               |
| ----- | ------------ | --------------------- |
| 0     | `/home`      | Dashboard             |
| 1     | `/entries`   | List + FAB            |
| 2     | `/analytics` | Tabbed analytics      |
| 3     | `/contacts`  | Suppliers / brokers   |
| 4     | `/settings`  | Profile, units, flags |


Deep links: `hexa://entries/:id`, `hexa://analytics/items/:itemKey`.

## State Management

- **Riverpod** or **Bloc** — pick one per team preference:
  - Riverpod: good for DI + async providers (PIP, analytics).
  - Bloc: explicit event/state for entry wizard.
- **Repository pattern:** `EntryRepository`, `AnalyticsRepository`, `AuthRepository` calling shared `ApiClient`.

## Realtime

- **SSE or WebSocket** channel: `wss://api/.../v1/businesses/{id}/events`
- On `entry.created` / `entry.updated`: invalidate `analyticsProvider` and home summary.
- Fallback: polling summary every 60s when socket disconnected.

## Offline Sync

1. Local store: **Drift** (SQLite) or **Isar** for outbox + cached entries.
2. User taps Save → write to outbox with `client_mutation_id`.
3. Worker syncs when online; on 409 conflict show merge UI (rare).
4. Read path: show cached data + stale-while-revalidate banner.

## Analytics UI

- **fl_chart** (or similar) for line/bar/pie.
- Heavy aggregates fetched once per filter change; chart data from API (precomputed).
- Item drill-down: push route with `itemKey` + date range.

## Price Intelligence Panel (PIP)

- **Trigger:** `debounce` 300ms on item field + price field changes.
- **Fetch:** `GET /price-intelligence?item=&current_price=`.
- **UI:** `SliverPersistentHeader` or pinned `Card` above keyboard; expand to full bottom sheet for chart + suppliers.

## Testing

- **Widget tests** for entry form validation and duplicate modal.
- **Golden tests** optional for dashboard cards.
- **Integration tests** against mock server or staging.

## iOS vs Android UX

- Shared layout; apply **Cupertino** motion for iOS settings sheets if desired.
- Safe area + keyboard insets on quick entry.
- Android back gesture: `PopScope` / `WillPopScope` for “discard draft?” on entry.

## Env per Flavor

- `dart-define` or `--dart-define-from-file=env/dev.json` for `API_BASE_URL` (no secrets in client except public keys if any).

