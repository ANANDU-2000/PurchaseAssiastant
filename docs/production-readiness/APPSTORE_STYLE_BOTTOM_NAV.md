# App Store style bottom navigation

## Problem

Operators needed clearer separation between the floating “New purchase” control and the tab row, plus more space above the home indicator.

## Current design

- `_ShellBottomBar` uses a single `Material` bar with four `_ShellNavTile` destinations and a detached circular `_FabButton` (`flutter_app/lib/features/shell/shell_screen.dart`).
- Tabs: Home, Reports, History, Search; FAB routes to `/purchase/new`.

## Fix (this pass)

- Dynamic bottom padding adds `20%` of `MediaQuery.viewPadding.bottom` beyond the `SafeArea` minimum so devices with a tall home indicator get extra breathing room without shrinking tap targets.

## Follow-up ideas (not required for stability)

- Optional `ClipRRect` + `BackdropFilter` blur behind the bar for a more “dock” aesthetic (watch GPU cost on low-end Android if enabled cross-platform).

## Verification

- Thumb-reach test on iPhone 16 Pro width: FAB and History icon should be reachable one-handed.
- Verify `hideShellChrome` routes (`/purchase`, `/reports`, `/assistant`) still hide the bar as expected.
