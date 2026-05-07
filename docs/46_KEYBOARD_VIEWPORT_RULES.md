# 46 — KEYBOARD_VIEWPORT_RULES

## Goal
On mobile, the focused field and the primary CTA must never be covered by the keyboard.

## Flutter building block
- `KeyboardSafeFormViewport` in:
  - `flutter_app/lib/shared/widgets/keyboard_safe_form_viewport.dart`

## Principles
- Sticky bottom CTA uses `AnimatedPadding` with `viewInsets.bottom`.
- Focused field scrolls into view using `Scrollable.ensureVisible(...)`.

