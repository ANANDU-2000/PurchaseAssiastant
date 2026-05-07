# 54 — OFFLINE_CACHE_STRATEGY

## Goal
Reports remain usable when offline / slow:
- show last known data (if available)
- refresh in background
- offer retry on failure

## Current implementation hooks
- Reports provider fetch timeout:
  - `flutter_app/lib/core/providers/reports_provider.dart`
- UI uses async-state + retry widgets:
  - `flutter_app/lib/features/reports/presentation/reports_page.dart`

