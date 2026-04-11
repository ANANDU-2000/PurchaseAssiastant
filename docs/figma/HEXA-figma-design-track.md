# HEXA — Figma design track (new workspace)

This document satisfies the **Figma design track** from the master plan when a live Figma MCP session is not available in the IDE.

## Create the workspace

1. In Figma, create a new team or project **HEXA Purchase Assistant**.
2. Enable your **published design system** library (or import the team library you use for mobile + web).
3. Create two top-level pages:
   - `Mobile App`
   - `Super Admin Web`

## Screen build order (design-system-first)

Follow the `figma-generate-design` workflow: wrapper frame first, then one section per `use_figma` script, tokens for color/spacing, component instances for buttons/cards/inputs.

1. Mobile — Home dashboard (hero KPI, top item, alerts strip, quick actions).
2. Mobile — Quick entry bottom sheet (lines, preview, duplicate confirm).
3. Mobile — Entries list + filters.
4. Mobile — Reports (tab bar: Overview, Items, Categories, Suppliers, Brokers).
5. Mobile — Item detail / Price intelligence expanded sheet.
6. Mobile — Supplier detail.
7. Web — Admin overview (metrics cards, API health placeholder).

## Handoff to engineering

- Export component names + property keys for Code Connect when components stabilize.
- Keep spacing on the 4/8 grid; document any one-off exceptions.

## Retention (iOS + Android)

- Bottom sheets for primary flows; avoid deep navigation for daily entry.
- Minimum 48dp touch targets for primary actions.
- High contrast for profit/loss and alert states.
