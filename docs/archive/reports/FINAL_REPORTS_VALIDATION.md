# Final Reports Validation

## Automated

```bash
cd flutter_app
flutter analyze lib/features/reports/
flutter test test/reports_page_smoke_test.dart test/reports_tab_deep_link_test.dart
```

## Manual checklist

| Area | Pass criteria |
|------|---------------|
| Navigation | 4 tabs visible; no More; URL sync |
| Search | Inline field filters Items/Purchases |
| Filters | Units/sort apply to list; badge count correct |
| Export | PDF/CSV uses filtered data |
| Overview | 9 KPIs visible before charts |
| Items | No Bag/Box/Tin chips; card shows qty/value/rate/count |
| Purchases | Supplier ranking + recent bills visible |
| Stock | Sections: current, low, out, dead, fast — no sub-tab row |
| Mobile 360px | One tab row; readable KPI grid |
| Deep links | `/stock/dead`, legacy `?tab=movement` land on Stock |

## Performance

- Tab switch < 1 frame jank (providers gated on `ShellBranch.reports`)
- Lists use `ListView.builder` / slivers
