# WhatsApp / share tracking (planned)

## Goal

Per purchase, surface lightweight metadata:

- WhatsApp shared (timestamp / flag)
- PDF generated
- Last opened (optional)
- Synced / pending sync (offline queue)

## Current state

History row does not yet render icon slots; **PDF share** already triggers `invalidatePurchaseWorkspace` so the list stays fresh.

## Implementation notes

- Persist flags on the purchase or a sidecar table; sync from backend when available.
- Keep icons **optional** and compact (14–16px) in the card trailing area or a single overflow menu to avoid clutter.
