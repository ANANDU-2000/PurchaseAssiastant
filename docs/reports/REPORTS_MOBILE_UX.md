# Reports Mobile UX

## Layout stack (phone)

1. **ReportsTopBar** — back, title, search field (expanded), filter icon, export icon
2. **ReportsPeriodBar** — compact preset chips (Wrap on narrow screens)
3. **ReportsPrimaryTabs** — 4 equal tabs, no horizontal scroll if fit
4. **Tab content** — single vertical scroll

## Rules

- Touch targets ≥ 48×48 dp on filter/export/back
- Typography: `HexaDsType` / theme title styles (no raw `fontSize: 10` in new code)
- No second horizontal chip row on Items or Stock
- Filter drawer: end-side `Drawer` or draggable sheet ≥ 85% height
- Keyboard-safe: `ScrollViewKeyboardDismissBehavior.onDrag`

## Stock tab

Vertical sections with section headers — no nested horizontal chips.

## Empty / error

Use `HexaEmptyState` / `FriendlyLoadError` — never raw `DioException`.
