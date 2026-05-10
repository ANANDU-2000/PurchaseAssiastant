# UI State Rebuild Audit

## Fixed
- Home shell provider: added timeout to `Connectivity().checkConnectivity()` and a hard timeout around the shell bundle fetch.
- Home dashboard provider: added connectivity timeout to prevent dashboard load stalls.
- Item unit dropdown: normalized stale `piece`/`pcs` values through resolved context and added bounded menu height.

## Remaining Risks
- `PurchaseItemEntrySheet` still owns text controllers for editing UX. Core unit meaning is now resolved centrally, but a deeper refactor should move draft `rateContext` and resolved unit context into provider state.
- Scanner edit sheet has its own unit state and should be migrated to `ResolvedItemUnitContext`.
