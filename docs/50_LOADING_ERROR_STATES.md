# 50 — LOADING_ERROR_STATES

## Goal
No infinite spinners; network failure shows fallback + retry.

## Reports timeout
- Provider uses a 10s timeout during page loops:
  - `flutter_app/lib/core/providers/reports_provider.dart`

## Retry pattern
- Screens use retry chips/buttons wired to provider refresh/invalidation.

