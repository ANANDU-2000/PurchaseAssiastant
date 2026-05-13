# Trader form accessibility (visual + motor)

## Touch targets

- Minimum **44×44** logical px for primary controls (`SegmentedButton` height, `FilledButton` height in wizard footer, suggestion rows — see `InlineSearchField` `minHeight: 44`).
- Wizard Continue / Save: height **56** / **60** (existing).

## Field readability

- Dense purchase fields use [densePurchaseFieldDecoration](../../flutter_app/lib/features/purchase/presentation/wizard/purchase_wizard_shared.dart): increased vertical `contentPadding`, explicit `floatingLabelBehavior`, and slightly taller `kPurchaseFieldHeight` to reduce **label/border** collisions.
- Design-system fields: [AppTextField](../../flutter_app/lib/core/design_system/widgets/app_text_field.dart) — increased vertical `contentPadding` and focus ring via [HexaOutlineInputBorder](../../flutter_app/lib/core/theme/hexa_outline_input_border.dart).

## Contrast

- Rest / focus / error borders must remain distinguishable in bright outdoor light — prefer tokenized colors (`HexaColors`, `HexaDsColors`) over ad-hoc greys in new code.

## Dynamic type

- Avoid fixed-height wrappers around `TextField` except `minHeight` via `ConstrainedBox` — terms step follows this pattern.

## Cross-links

- [IOS_KEYBOARD_OVERLAY_AUDIT.md](./IOS_KEYBOARD_OVERLAY_AUDIT.md)
