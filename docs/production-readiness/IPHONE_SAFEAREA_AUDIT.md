# iPhone safe-area audit

## Problem

Bottom chrome sat too close to the home indicator; CTAs felt cramped on tall iPhones.

## Root cause

Shell bottom padding used a fixed `EdgeInsets` and relied solely on `SafeArea` without extra breathing room proportional to `MediaQuery.viewPadding`.

## Fix

- `_ShellBottomBar` in `flutter_app/lib/features/shell/shell_screen.dart` now adds `math.max(0, MediaQuery.viewPaddingOf(context).bottom * 0.2)` to the bottom padding inside the existing `SafeArea`, giving a slightly larger gap on devices with a home indicator without double-counting the full inset.

## Related surfaces

- Purchase wizard footer already pads with `MediaQuery.viewInsetsOf(ctx).bottom` (`purchase_entry_wizard_v2.dart`).
- `KeyboardSafeFormViewport` documents safe-area vs inset rules (`keyboard_safe_form_viewport.dart`).

## Verification

- Run on iPhone 15/16 class simulator: bottom nav labels and FAB should clear the gesture bar with comfortable spacing.
- Rotate to landscape: bar should not clip.
