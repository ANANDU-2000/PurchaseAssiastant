# Flutter tests

Run from `flutter_app/`:

```bash
flutter test
```

## Layout

| Area | Folder / files |
|------|----------------|
| Unit / logic | `*_test.dart` at repo root of `test/` |
| Feature widgets | `test/features/<domain>/` |
| Shared helpers | `responsive_test_utils.dart` (layout smoke only) |

## Conventions

- Prefer **unit tests** for `StockRowMetrics`, parsers, and report aggregates (fast, no pump).
- Use **widget tests** with `ProviderScope` + session overrides when a page needs auth (see `reports_page_smoke_test.dart`, `staff_home_page_smoke_test.dart`).
- Do not add duplicate shell smoke tests in `widget_test.dart` — use the dedicated `*_smoke_test.dart` for that route.

## CI

Match repo rule: `flutter analyze` + `flutter test` on PRs.
