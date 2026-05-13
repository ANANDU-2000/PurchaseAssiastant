# CTA and keyboard behavior

## Architectural decision (single source of truth)

**Chosen pattern: Option A — `resizeToAvoidBottomInset: true` on primary trader `Scaffold`s**, with:

- **No** extra `MediaQuery.viewInsets.bottom` inside **scroll padding** for the same scaffold body (avoids **double-counting**).
- Footer / pinned CTAs use **`SafeArea` + home-indicator padding only**, unless a parent explicitly opts out of resize (then use `KeyboardSafeFormViewport.useViewInsetBottom: true` per widget contract).

**Rationale:** Flutter already shrinks the body when the IME opens. Manual `kb` padding on both scroll **and** footer (previous wizard pattern with `resizeToAvoidBottomInset: false`) duplicated inset math and caused “jumpy” or overlapping CTAs on small phones.

## `KeyboardSafeFormViewport` contract

From [keyboard_safe_form_viewport.dart](../../flutter_app/lib/shared/widgets/keyboard_safe_form_viewport.dart):

- Default `useViewInsetBottom: false` when parent `Scaffold.resizeToAvoidBottomInset == true`.
- Set `useViewInsetBottom: true` **only** when a parent keeps `resizeToAvoidBottomInset: false` (e.g. legacy auth shells).

## Pinned vs in-lane CTAs

| Pattern | When to use |
|---------|----------------|
| **In-lane** (inside `KeyboardSafeFormViewport` footer slot) | Full-screen forms ([FullScreenFormScaffold](../../flutter_app/lib/shared/widgets/full_screen_form_scaffold.dart)), full-page item entry — footer scrolls with content but gets bottom safe padding. |
| **Pinned below body** | Purchase wizard: `Column(Expanded(scroll), footer)` — with **resize: true**, footer stays **above** keyboard because the scaffold body height shrinks. |

## Purchase wizard migration

`purchase_entry_wizard_v2.dart`:

- `resizeToAvoidBottomInset: **true**`
- `SingleChildScrollView` padding for steps 0,1,3: **fixed** `EdgeInsets.fromLTRB(16, 16, 16, 16)` (no `kb` term).
- Step 2: unchanged outer `Padding` + inner `Expanded` + `ListView` (see [FORM_SCROLL_ARCHITECTURE.md](./FORM_SCROLL_ARCHITECTURE.md)).
- Footer: `SafeArea(top: false)` + padding `EdgeInsets.fromLTRB(16, 8, 16, 8)` — **no** `kb + 8` inset.

## Related docs

- [IOS_KEYBOARD_OVERLAY_AUDIT.md](./IOS_KEYBOARD_OVERLAY_AUDIT.md)
- [SAFE_AREA_AND_INSET_FIXES.md](./SAFE_AREA_AND_INSET_FIXES.md)
