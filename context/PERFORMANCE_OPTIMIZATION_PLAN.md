# Performance optimization plan (purchase item entry)

## Hot paths

- `_liveTotalsCard` rebuilds on every controller tick via `ListenableBuilder` + `_lineTotalsListenable`.
- Catalog `_catalogSearchItems` rebuild (sync) on init — acceptable for N < 2k; async chunking if reintroduced.

## Actions

1. Wrap preview subtree in **`RepaintBoundary`**.
2. Split preview into `StatefulWidget` with `Listenable.merge` local scope (optional follow-up).
3. Avoid `setState` on entire 4k-line sheet for tax toggle — local `ValueNotifier<bool>` for tax chip + `ValueListenableBuilder` (incremental).
4. Debounce remote suggest calls (party field already debounced).

## Metrics

- DevTools timeline: frame build < 16ms median while typing rate on mid device.
