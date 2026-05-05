# CURSOR AGENT — MASTER RULES

> Read this file FIRST before any task. All other MD files reference these rules.

---

## PROJECT IDENTITY

- **App:** PurchaseAssistant — commodity trading purchase management
- **Stack:** Flutter (Riverpod + GoRouter) + FastAPI + SQLAlchemy async + Supabase Postgres
- **Target device:** iPhone 16 Pro (393×852pt logical, safe-area top≈59pt bottom≈34pt)
- **Theme color:** `HexaColors.brandPrimary = #1B6B5A` (dark teal)

## HOW TO USE THESE MD FILES

Each MD file in `.cursor/` covers one feature area. Every file has:

- `## STATUS` — ✅ Done / ⚠️ Partial / ❌ Not started
- `## WHAT TO DO` — exact task list, tick off as you go
- `## FILES` — exact file paths to edit
- `## SPEC` — exact UI/logic/code to implement
- `## VALIDATION` — how to verify it works

When you start a task:

1. Read the relevant MD file
2. Check STATUS section — skip ✅ items
3. Work through ⚠️ and ❌ items only
4. Update STATUS after each item
5. Never modify ✅ sections

---

## ABSOLUTE RULES (never break these)

### DO NOT CHANGE

- `PurchaseDraft` model fields/JSON keys
- `OfflineStore` key scheme
- GoRouter route names and paths
- `HexaColors` constants
- Backend Pydantic request schemas for `POST /purchases`
- Any file in `test/` directory
- `alembic/versions/` files (migrations are immutable)

### ALWAYS DO

- Use `KeyboardSafeFormViewport` or `MediaQuery.viewInsetsOf(context)` for keyboard awareness
- Use `InkWell` (not `GestureDetector`) for all tappable suggestion tiles
- Call parent `onSelected` BEFORE `controller.value` update in `_pick()`
- Wrap every API call in try/catch with user-visible SnackBar on error
- Use `OfflineStore.getPurchaseWizardDraft()` for draft persistence
- Show `CircularProgressIndicator` inside buttons while async op runs
- Disable buttons while `_isSaving == true`

### CODE STYLE

- Max line length: 100 chars
- All currency: `₹${amount.toStringAsFixed(2)}` — no "INR" prefix
- All weight: `${kg}kg` or `${bags} bags • ${kg}kg`
- Date display: `dd MMM yyyy` format via `intl` package
- Status chips: paid=green, pending=orange, overdue=red, draft=amber

### ERROR HANDLING PATTERN

```dart
// Every async button action:
setState(() => _isSaving = true);
try {
  await _doWork();
  if (!mounted) return;
  // success
} on DioException catch (e) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_friendlyError(e)), backgroundColor: Colors.red),
  );
} catch (e) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
  );
} finally {
  if (mounted) setState(() => _isSaving = false);
}
```

### WHAT "FIXED" MEANS IN STATUS

- ✅ = implemented AND manually tested on device/simulator
- ⚠️ = code exists but has known gap or untested
- ❌ = not implemented at all

---

## CURRENT VERIFIED STATUS (as of latest zip)


| Feature                                               | Status                                 |
| ----------------------------------------------------- | -------------------------------------- |
| Suggestion tap (supplier/broker) — `_pick()` sync     | ✅ Fixed                                |
| Keyboard overlap — `viewInsetsOf` + `AnimatedPadding` | ⚠️ Partial (item sheet still overlaps) |
| Auto-advance without broker                           | ✅ Removed                              |
| Draft auto-save + resume banner                       | ✅ Banner exists                        |
| Reports date filter (purchase_date not created_at)    | ✅ Fixed in trade_query.py              |
| DB pool pre_ping                                      | ✅ Added                                |
| Bag qty label ("No. of bags")                         | ❌ Not done                             |
| Live calc preview (bags × kg/bag = total)             | ❌ Not done                             |
| Compact history list cards                            | ❌ Not done                             |
| Purchase detail page redesign                         | ❌ Not done                             |
| Line display helper (bags • kg)                       | ❌ Not done                             |
| Terms step — commission unit picker                   | ⚠️ Modes exist, unit per bag missing   |
| Broker statement PDF                                  | ❌ Not done                             |
| WhatsApp auto-report schedule                         | ⚠️ MVP sheet exists, no scheduling     |
| Settings cleanup                                      | ❌ Not done                             |
| Print button in detail                                | ❌ Not done                             |
| Supabase broker images                                | ❌ Not done                             |
| Reports page gray text                                | ❌ Not done                             |
| "Total spend" removed everywhere                      | ❌ Not done                             |


---

## SESSION WORKFLOW

Start every Cursor session by running:

```
@.cursor/00_AGENT_RULES.md
```

Then reference the specific MD file:

```
@.cursor/02_ITEM_ENTRY.md  implement all ❌ items
```

