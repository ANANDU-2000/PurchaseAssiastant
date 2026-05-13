# Final form production readiness

## Documentation set

1. [IOS_KEYBOARD_OVERLAY_AUDIT.md](./IOS_KEYBOARD_OVERLAY_AUDIT.md)
2. [FORM_FOCUS_FLOW_REBUILD.md](./FORM_FOCUS_FLOW_REBUILD.md)
3. [CTA_AND_KEYBOARD_BEHAVIOR.md](./CTA_AND_KEYBOARD_BEHAVIOR.md)
4. [SAFE_AREA_AND_INSET_FIXES.md](./SAFE_AREA_AND_INSET_FIXES.md)
5. [DROPDOWN_OVERLAY_FIXES.md](./DROPDOWN_OVERLAY_FIXES.md)
6. [FORM_SCROLL_ARCHITECTURE.md](./FORM_SCROLL_ARCHITECTURE.md)
7. [TRADER_FORM_ACCESSIBILITY.md](./TRADER_FORM_ACCESSIBILITY.md)
8. [NEXT_FIELD_NAVIGATION_SYSTEM.md](./NEXT_FIELD_NAVIGATION_SYSTEM.md)
9. [MOBILE_FORM_PERFORMANCE_PLAN.md](./MOBILE_FORM_PERFORMANCE_PLAN.md)
10. This checklist

## Legacy cross-links

- [IOS_KEYBOARD_OVERLAY_FIXES.md](../IOS_KEYBOARD_OVERLAY_FIXES.md)
- [SUPPLIER_BROKER_DROPDOWN_FIXES.md](../SUPPLIER_BROKER_DROPDOWN_FIXES.md)

## Device matrix (manual QA)

| Device | OS | Cases |
|--------|-----|--------|
| iPhone 16 Pro (or simulator) | iOS 18+ | Party Next chain; Terms Next; Items list scroll + keyboard; full-page Add Item pinned Save |
| iPhone SE (small) | iOS | Same + verify no label overlap on Terms |
| Pixel-class | Android 14+ | Same flows + hardware keyboard Tab (optional) |
| Narrow width (360×780) emulator | Android | Wizard footer never under keyboard; dropdown max height |

## Automated checks (repo)

- Run: `flutter analyze` (project root `flutter_app/`) — **passed** on implementation pass.
- Targeted: `flutter test test/purchase_draft_calc_test.dart test/trade_purchase_line_money_contract_test.dart` — **passed**.
- Broader `flutter test` optional before release.

## Sign-off criteria

- [ ] No focused field hidden under IME or accessory bar (iOS).
- [ ] Continue / Save never drawn under keyboard on wizard and item entry.
- [ ] Supplier/broker suggestions selectable while keyboard open.
- [ ] No unbounded `Column` + `ListView` regressions on Items step.
- [ ] `flutter analyze` clean for touched files.

## Implementation status (this pass)

- Wizard scaffold migrated to **`resizeToAvoidBottomInset: true`** with footer safe-area padding (no double `viewInsets` in scroll).
- Terms step: **focus traversal** + **payment days auto-focus** after Party advance.
- Shared **iOS accessory allowance** constant for `scrollPadding`, `InlineSearchField` options height, and **party overlay** usable height.
- `AppTextField` + dense purchase decoration spacing tweaks.
- Wizard `AnimatedSwitcher` child wrapped in **`RepaintBoundary`** (step paint isolation).
