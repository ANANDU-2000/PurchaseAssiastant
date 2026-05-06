# 09 — Offline Sync (Drafts + Queue)

## Must support

- Local cached lists (history, suppliers, brokers, catalog)
- Offline drafts for purchase entry (including scanner drafts)
- Queued sync when connection returns
- Optimistic UI for saves/edits (with rollback on failure)

## Baseline implementation

- Drafts in Hive (already used by purchase wizard)
- Lightweight queued operations table:
  - create_trade_purchase
  - update_trade_purchase
- Retry with exponential backoff

## Never

- Silent data loss
- “Manual refresh” buttons as primary recovery

