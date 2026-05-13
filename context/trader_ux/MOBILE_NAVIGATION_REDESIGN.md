# Mobile navigation redesign

## Summary of changes

| Element | Before | After |
|---------|--------|--------|
| Bottom bar | `BottomAppBar` + centre notch + centre FAB | `NavigationBar` (M3) + **`FloatingActionButtonLocation.endContained`** |
| Tab 4 label | Assistant | **Search** |
| Assistant | Shell tab `/assistant` | **Push route** `/assistant` (full screen) |
| Global `/search` push route | Standalone `GoRoute` | **Removed** — search is shell tab only |
| FAB | Centre-docked | **End-contained** (thumb-aligned right) |

## Files

- `flutter_app/lib/features/shell/shell_screen.dart`
- `flutter_app/lib/features/shell/shell_branch_provider.dart` — `ShellBranch.search`
- `flutter_app/lib/core/router/app_router.dart` — branches + assistant route

## Shell chrome hide rules

Chrome still hidden on `/reports`, `/purchase` subtree (wizard overlap policy unchanged), and **`/assistant`** push (composer layout).

## Cross-links

- `GLOBAL_SEARCH_REARCHITECTURE.md`
- `THUMB_REACHABILITY_AUDIT.md`
