# Mobile touch & scroll fixes

## Principles

1. **No competing vertical drags**: parent `SingleChildScrollView` vs child list — prefer inline suggestions OR bounded overlay list, never both capturing vertical drag without `NotificationListener`.
2. **Opaque hit targets** on suggestion rows (`HitTestBehavior.opaque` / `Material`).
3. **Primary scroll** only on `KeyboardSafeFormViewport` for full-page add item.

## Party inline field

- Documented design: suggestions are **not** in nested `ListView` — keep for stability.
- If jitter returns: wrap suggestion column in `ScrollConfiguration` with `ClampingScrollPhysics` and `BouncingScrollPhysics` never on web.

## Inline overlay autocomplete

- Confirm `Listener` + `InkWell` doesn’t steal scroll: if issues persist, switch row to `ListTile` + `onTap` only (remove `onPointerDown` commit).

## QA gestures

- Slow scroll through 20+ suppliers without selection changing.
- Flings end without snapping field focus closed.
