# Responsive overflow audit

## Checked / adjusted in this pass

- **Shell**: Switched to `NavigationBar` + `endContained` FAB to avoid centre-notch clipping on narrow devices.
- **Search tab**: `embeddedInShell` removes back `leading` to avoid empty leading gap (Material `automaticallyImplyLeading: false`).

## Still to verify on devices

| Screen | Areas |
|--------|--------|
| iPhone 16 Pro (safe areas) | `NavigationBar` + FAB overlap with home indicator |
| Small Android (360dp) | Purchase history horizontal `FilterChip` row — already `ListView` horizontal |
| Tablet | Whether `NavigationBar` should switch to rail (future) |

## Known historical issues

- Purchase wizard hides shell chrome — documented in `shell_screen.dart` `hideShellChrome`.
- Reports full-screen branch hides shell — unchanged.

## Cross-links

- `THUMB_REACHABILITY_AUDIT.md`
- `MOBILE_NAVIGATION_REDESIGN.md`
