# Thumb reachability audit

## Primary actions (target: right thumb, bottom)

| Action | Location after redesign | Status |
|--------|-------------------------|--------|
| New purchase | FAB `endContained` on shell | **Improved** (was centre notch) |
| Global search | Bottom nav **Search** tab | **Improved** |
| History | Bottom nav | Unchanged |
| Home / Reports | Bottom nav | Unchanged |

## Secondary actions (top — acceptable)

| Action | Location |
|--------|----------|
| Settings | `AppSettingsAction` trailing on `ShellQuickRefActions` |
| Assistant | Toolbar icon → `/assistant` |
| Catalog / Contacts | Toolbar |

## Home-specific

- `ShellQuickRefActions(..., suppressToolbarSearch: true)` avoids duplicating Search at top-right.

## Follow-ups

- Audit **Reports** and **Purchase wizard** for FAB / bottom padding on small devices (`RESPONSIVE_OVERFLOW_AUDIT.md`).
- Consider **floating** “mark delivered” on history cards as bottom sheet bulk actions (future).

## Cross-links

- `MOBILE_NAVIGATION_REDESIGN.md`
- `RESPONSIVE_OVERFLOW_AUDIT.md`
