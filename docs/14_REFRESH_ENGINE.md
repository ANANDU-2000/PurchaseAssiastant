# 14 — Refresh Engine (Auto Invalidate, No Manual Refresh)

## Rule

After any mutation (save/edit/mark paid/delete), the app must refresh silently.

## Required behaviour

- Optimistic updates for lists
- `ref.invalidate(...)` after successful mutations
- Background refresh for report snapshots

## Forbidden

- Manual refresh buttons as primary “fix”
- Stale lists after save

