# Mobile form performance plan

## Hot paths

| Area | Symptom | Mitigation |
|------|---------|------------|
| `PurchaseItemEntrySheet` | Controllers merged into `Listenable.merge` rebuild wide subtree | Keep `RepaintBoundary` on live preview; avoid adding listeners to the whole wizard for per-keystroke work. |
| `purchase_entry_wizard_v2` | `ref.watch` on large selectors | Prefer `select` + narrow rebuilds (already used in places); avoid watching full draft for static chrome. |
| `AppTextField` | `controller.addListener(setState)` | Required for error/helper sync — acceptable; avoid wrapping entire screens in parent `setState`. |
| Party / inline overlays | Overlay rebuild on each frame | Keep overlay diffing minimal (`_syncSuggestionOverlay` only when visibility changes). |

## DevTools checklist (manual)

1. **Performance overlay** — GPU thread budget during keyboard open/close on item entry.
2. **Rebuild counts** — enable “Track widget rebuilds”; type in supplier field; ensure party row only rebuilds supplier subtree.
3. **Repaint rainbow** — verify pinned preview is isolated.

## Wizard micro-optimization

- Wrap `AnimatedSwitcher` child in `RepaintBoundary` to isolate step transitions (implemented in code when low-risk).

## Future

- Consider `HookConsumerWidget` / `Riverpod` `select` for item entry preview model only if profiling shows jank on low-end Android.
