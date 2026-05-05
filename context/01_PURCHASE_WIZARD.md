# SPEC 01 — PURCHASE ENTRY WIZARD

> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS


| Task                                                          | Status                  |
| ------------------------------------------------------------- | ----------------------- |
| 3-step wizard flow (party → items → terms)                    | ✅ Done                  |
| Suggestion tap — `_pick()` sync fix                           | ✅ Done                  |
| Keyboard overlap — wizard body                                | ⚠️ Implemented (verify) |
| Keyboard overlap — item entry sheet                           | ❌ Not done              |
| Auto-advance removed (supplier pick stays on party step)      | ✅ Done                  |
| Exit guard (PopScope + discard dialog)                        | ✅ Done                  |
| Draft auto-save every 800ms                                   | ✅ Done                  |
| Resume draft banner on home                                   | ✅ Done                  |
| "New supplier" / "New broker" — Navigator rootNavigator       | ✅ Done                  |
| Bottom bar always above keyboard                              | ⚠️ Implemented (verify) |
| Single "Continue" button on party step (no Save draft button) | ⚠️ Implemented (verify) |


---

## FILES TO EDIT

```
flutter_app/lib/features/purchase/presentation/purchase_entry_wizard_v2.dart
flutter_app/lib/features/purchase/presentation/wizard/purchase_party_step.dart
flutter_app/lib/features/purchase/presentation/wizard/purchase_terms_only_step.dart
flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart
```

---

## WHAT TO DO

### ⚠️ TASK 01-A: Remove "Save draft" button from party step UI

**File:** `purchase_party_step.dart`

The "Save draft" button on the party step must be removed from the visible UI.
Draft saving is automatic — no manual button needed.

Find in `purchase_party_step.dart` any `OutlinedButton` or `ElevatedButton` with text "Save draft".
Remove the button widget entirely. Keep only the "Continue" button on this step.

---

### ⚠️ TASK 01-B: Fix bottom bar — keyboard still overlaps on iPhone 16 Pro

**File:** `purchase_entry_wizard_v2.dart`

Current state: `AnimatedPadding` is applied but `bodyContext` may not have the keyboard inset.

**Find `_buildKeyboardAwareBody` or the main Scaffold body builder.** Replace with:

```dart
Widget _buildWizardBody(BuildContext context, Widget stepContent, bool isEdit) {
  return MediaQuery.removePadding(
    context: context,
    removeTop: false,
    child: LayoutBuilder(
      builder: (ctx, _) {
        final kb = MediaQuery.viewInsetsOf(ctx).bottom;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(16, 16, 16, kb > 0 ? 8 : 16),
                child: stepContent,
              ),
            ),
            // Bottom buttons always above keyboard — no overlap possible
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              color: Theme.of(ctx).scaffoldBackgroundColor,
              padding: EdgeInsets.fromLTRB(16, 8, 16, kb > 0 ? kb + 8 : 16),
              child: _buildBottomBar(ctx, isEdit),
            ),
          ],
        );
      },
    ),
  );
}
```

Ensure `resizeToAvoidBottomInset: false` on the wizard Scaffold (we handle it manually).

---

### ⚠️ TASK 01-C: Party step — more vertical space above fields

**File:** `purchase_party_step.dart`

Current: Supplier and broker fields are crammed near top. Suggestions panel has no room.

Add `const SizedBox(height: 240)` at the BOTTOM of the fields column.
This gives the suggestion panel room to render below the broker field
without overlapping the Continue button.

**Party step full column order:**

```
[PUR-ID + Date row]
[24px gap]
[Supplier label]
[Supplier field]
[suggestions panel — inline, below field]
[20px gap]
[Broker label]
[Broker field]  
[suggestions panel — inline, below field]
[240px spacer — ensures suggestions never overlap Continue button]
```

---

## WORKFLOW: 3 STEPS

```
STEP 0 — PARTY
  Supplier (required) + Broker (optional)
  [Continue →]  ← disabled until supplier selected

STEP 1 — ITEMS  
  Items list + [+ Add Item] button
  [Continue →]  ← disabled until ≥1 item added

STEP 2 — TERMS
  Editable: payment days, commission, discount, freight, billty, delivered
  Cost breakdown summary
  [Save Purchase]

→ SAVED SHEET → redirect home
```

---

## SPEC: Wizard AppBar per step

```
Step 0: AppBar title = "New Purchase"  (or "Edit Purchase" on edit)
Step 1: AppBar title = "New purchase — Items"
Step 2: AppBar title = "New purchase — Terms"

AppBar leading: always shows ← back arrow (PopScope handles exit guard)
AppBar trailing: [PUR-XXXX] chip on Step 0, nothing on Steps 1–2
```

---

## VALIDATION

- Tap supplier → type → tap suggestion → stays on party step
- Tap Continue → moves to items step (supplier required, broker optional)
- Press back from step 1 with items → discard dialog
- Keyboard opens → Continue button stays above keyboard on all steps
- No "Save draft" button visible on party step
- Suggestion panel never overlaps Continue button

