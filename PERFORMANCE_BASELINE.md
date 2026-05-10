# Performance baseline

**Status:** Placeholder — populate after first profiling pass (see `PERFORMANCE_AUDIT.md`).

| Metric | Baseline (ms) | Target (ms) | Date |
|--------|---------------|-------------|------|
| `/home` cold | TBD | 700 | |
| `/purchase/new` open | TBD | 500 | |
| `/reports` first frame | TBD | 700 | |
| Search debounce effective | TBD | 120 | |

Use Flutter DevTools Timeline + Network, and Postgres `EXPLAIN ANALYZE` for report SQL.
