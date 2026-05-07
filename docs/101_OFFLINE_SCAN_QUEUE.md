# 101 — OFFLINE_SCAN_QUEUE

## Goal

Never lose a scan when the network is slow or temporarily unavailable.

## Flutter behavior

- Capture photo → compress → queue job locally when offline/timeout
- Retry upload automatically in background or via “Resume offline scan”

Reference:

- `flutter_app/lib/core/services/offline_store.dart`
- `flutter_app/lib/features/purchase/presentation/scan_purchase_v2_page.dart`

## Backend behavior

- Scanner v3 returns `scan_token` immediately (fast start)
- Client polls status with exponential backoff if needed

## UX rules

- Never show “No internet” unless connectivity is actually offline.
- For timeouts: show “Upload taking longer — retrying”.

