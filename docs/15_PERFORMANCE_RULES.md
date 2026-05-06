# 15 — Performance Rules

## Targets

- Scan-to-preview: < 6s on average 4G
- Purchase save: < 2s
- Reports load: < 2s for common ranges

## Rules

- Avoid heavy rebuilds in tables/lists (`const`, memoization where needed)
- No `IntrinsicHeight` in long lists
- Use server-side aggregations for reports
- Use cached snapshots + `keepAlive` providers for shell tabs

