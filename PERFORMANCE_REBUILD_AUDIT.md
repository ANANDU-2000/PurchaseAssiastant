# Performance Rebuild Audit

## Repairs
- Home non-category tabs no longer wait forever on connectivity plugin calls.
- Shell report bundle now always resolves, clearing inflight dedupe and avoiding stuck loading UI.
- Item dropdown choices are derived from a small resolved context and bounded menu, keeping interaction lightweight.

## Targets
- Item entry instant: central resolver is synchronous and map-based.
- Dropdown under 100ms: no network call is performed when opening the dropdown.
- Tab switch under 150ms: shell cache remains used; hung fetches are capped.

## Remaining Work
- Reduce nested watches in scanner and report pages after the unit-context migration is applied there.
- Add profiling around purchase wizard rebuilds after scanner state migration.
