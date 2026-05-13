# Safe area and inset fixes

## Principles

1. **Notch / Dynamic Island:** Prefer outer `SafeArea` on routes that draw edge-to-edge; inner `SafeArea(top: false)` when the `AppBar` already consumes top inset.
2. **Home indicator:** Any **pinned** footer CTA row should include bottom safe padding (`SafeArea` or `MediaQuery.paddingOf(context).bottom`).
3. **Modal bottom sheets:** Use `useSafeArea: true` where supported, and/or wrap content with `SafeArea` + `Padding(bottom: MediaQuery.viewInsetsOf(ctx).bottom)` **only** when the modal’s scaffold does **not** resize (see [CTA_AND_KEYBOARD_BEHAVIOR.md](./CTA_AND_KEYBOARD_BEHAVIOR.md)).

## Known patterns in repo

| Location | Pattern |
|----------|---------|
| `purchase_entry_wizard_v2` body | `SafeArea(bottom: false)` on outer body — footer chrome applies `SafeArea` for home indicator |
| `FullScreenFormScaffold` | `SafeArea(top: false, bottom: false, left/right: true)` + `KeyboardSafeFormViewport` footer uses inner `SafeArea(top: false, maintainBottomViewPadding: true)` |
| `showModalBottomSheet` builders | Mixed: many add `viewInsets` padding manually — audit when touching each sheet |

## Landscape

- Trader flows are portrait-first; if landscape is enabled, re-verify `maxWidth` constraints on overlays and that `AlertDialog` / `BottomSheet` do not clip.

## Cross-links

- [IOS_KEYBOARD_OVERLAY_AUDIT.md](./IOS_KEYBOARD_OVERLAY_AUDIT.md)
