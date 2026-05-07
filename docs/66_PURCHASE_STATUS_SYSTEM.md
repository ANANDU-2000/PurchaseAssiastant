# Purchase status system (History UI)

## Backend / model

`PurchaseStatus` mirrors API strings (`derived_status` / `status`). Chips on cards use compact trader-facing labels, not full ERP spellings.

## Quick filter semantics

- **All** — no primary filter.
- **Due** — client bucket for payments needing attention (see `64_HISTORY_FILTER_SYSTEM.md`).
- **Paid** — API `paid`.
- **Draft** — API `draft`.

## Sheet shortcuts

- Pending (confirmed) — secondary `pending`.
- Overdue — secondary `overdue` + API.
- Paid — primary `paid` (same as chip).
