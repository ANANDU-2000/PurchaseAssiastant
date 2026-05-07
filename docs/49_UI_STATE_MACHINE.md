# 49 — UI_STATE_MACHINE

## Goal
Every screen has predictable states:
- loading
- success
- empty
- error + retry

## Examples
- Reports page uses provider-driven async state:
  - `flutter_app/lib/features/reports/presentation/reports_page.dart`
- Purchase detail uses a dedicated provider and retry UI:
  - `flutter_app/lib/features/purchase/presentation/purchase_detail_page.dart`
- Standard error widget:
  - `flutter_app/lib/core/widgets/friendly_load_error.dart`

