# 103 — RETRY_AND_TIMEOUT_SYSTEM

## Goal

Replace false “No internet” errors with correct timeout/retry behavior.

## Client rules

- **Timeout ≠ offline**
- Use:
  - receive timeout handling (slow backend) → retry with backoff
  - connect timeout handling (no route) → offline queue

## Server rules

- Start endpoint must return quickly (token issued immediately).
- Status endpoint must be fast and safe (poll-friendly).

## Backoff

Recommended:

- poll every 300–600ms while progressing quickly
- widen to 1–2s if stage stalls
- total budget 90–120s before showing “still working” state

