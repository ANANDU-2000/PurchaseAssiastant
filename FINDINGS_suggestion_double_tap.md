# FINDINGS: Broker/Supplier + Item Suggestion "Needs Two Taps to Select" (Issue #1)

**Status:** Root cause NOT confirmed — needs on-device trace. Heavy scar tissue in widget suggests race between focus-loss and tap landing.

---

## Widget & Call Sites

| File | Role |
|------|------|
| `flutter_app/lib/features/purchase/presentation/widgets/party_inline_suggest_field.dart` | Shared suggestion widget (`PartyInlineSuggestField`) |
| `flutter_app/lib/features/purchase/presentation/wizard/purchase_party_step.dart` | Broker/Supplier pick (lines 393–418, 588–612) |
| `flutter_app/lib/features/purchase/presentation/widgets/purchase_item_entry_sheet.dart` | Item pick (line ~3441) |

All three use `suggestionsAsOverlay: true` (overlay mode).

---

## Full Tap-to-Select Path (Overlay Mode)

```
User taps suggestion tile in overlay
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. InkWell.onTap (line 639) → commit() → _pick(it)         │
│    • _pickInProgress check (line 555)                        │
│    • _consumeIfDuplicatePick() 400ms de-dupe (line 556)     │
│    • Sets _pickInProgress = true (line 557)                 │
│    • Cancels grace timer (line 558)                         │
│    • _suppressPanelAfterPick = true (line 561)              │
│    • If overlay showing: _hideSuggestionOverlay() (567-569) │
│    • applyPick() — sync (non-overlay) OR post-frame (overlay)│
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. applyPick() (lines 571–613)                              │
│    • widget.onSelected?.call(it) (line 575)                 │
│    • Updates controller.text (lines 578–581)                │
│    • setState: _filterQuery, _suppressPanelAfterPick (584)  │
│    • _scheduleOverlaySync() if not overlay (line 590)       │
│    • If !keepFocus: requestFocus(next) OR unfocus (599-609) │
│    • finally: _pickInProgress = false (line 612)            │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
Parent receives onSelected → updates draft, moves focus, etc.
```

---

## Concurrent Focus-Loss Path (The Race)

```
User taps suggestion in overlay
        │
        ▼ (simultaneously)
TextField loses focus (overlay is separate layer)
        │
        ▼
_listenFocus() fires (lines 373–411)
        │
        ├─ nowFocused = false (line 374)
        ├─ _flushFilterToLive() (line 398)
        ├─ _armSuggestPanelGraceIfNeeded() (line 404)
        │     │
        │     ├─ Sets _suggestPanelGrace = true (line 318)
        │     ├─ Starts 800ms Timer (line 319)
        │     └─ Timer callback: _suggestPanelGrace = false, setState, _scheduleOverlaySync()
        │
        ├─ setState(() {}) (line 405)  ← SYNCHRONOUS
        └─ addPostFrameCallback: setState + _scheduleOverlaySync() (lines 406–410)
```

---

## Overlay Visibility Logic

`_panelVisibleForOverlay()` (lines 830–844) — **gate for showing overlay**:
```dart
final suggestInteractive = widget.focusNode.hasFocus ||
    _suggestPanelGrace ||
    (widget.suggestionsAsOverlay && _overlayStayOpenUntilDismiss);
return !locked &&
    !_suppressPanelAfterPick &&
    suggestInteractive &&
    (rows.isNotEmpty || showAddFocused);
```

`_syncSuggestionOverlay()` (lines 846–858) — **actually shows/hides overlay**:
```dart
if (!_panelVisibleForOverlay()) {
    if (_overlayController.isShowing) _overlayController.hide();
    return;
}
if (!_overlayController.isShowing) _overlayController.show();
```

**Called from** (all via `_scheduleOverlaySync()` → `addPostFrameCallback`):
- `build()` (line 1262)
- `_listenFocus` post-frame (line 410)
- `_listenCtrl` → `_maybeRevealAfterFilter` (line 354)
- `_pick()` after apply (line 590)
- `_onKey` (line 778)

---

## The Race Window (Hypothesis)

| Time | Focus-Loss Path | Tap Path |
|------|-----------------|----------|
| T0 | User taps suggestion tile in overlay | |
| T1 | TextField loses focus → `_listenFocus` runs | |
| T2 | `_armSuggestPanelGraceIfNeeded()`: `_suggestPanelGrace = true`, starts 800ms timer | |
| T3 | `setState()` (line 405) → rebuild | |
| T4 | `addPostFrameCallback` queued for `_syncSuggestionOverlay()` | Tap event delivered to `InkWell.onTap` |
| T5 | | `_pick()` runs: `_pickInProgress=false`, `_consumeIfDuplicatePick=false` |
| T6 | | `_pickInProgress = true`, `_hideSuggestionOverlay()` → `_overlayController.hide()` |
| T7 | | `applyPick()` scheduled via `addPostFrameCallback` (line 619) |
| T8 | **Frame boundary** | |
| T9 | `_syncSuggestionOverlay()` runs: `_panelVisibleForOverlay()` = true (grace still on) → `_overlayController.show()` | `applyPick()` runs: `onSelected`, controller update, `_pickInProgress = false` |
| T10 | Overlay re-shown briefly (800ms timer still running) | |

**Result:** First tap calls `_pick()` but overlay is hidden at T6. The `addPostFrameCallback` for `applyPick()` runs at T9, **after** the overlay is re-shown by the grace timer's post-frame callback. The `onSelected` callback fires but the UI may have flickered.

**Why second tap works:** By then, `_pickInProgress = false`, `_suppressPanelAfterPick = true`, focus has moved to next field — no race.

---

## Existing Guards (Scar Tissue)

| Guard | Location | Purpose | May Be Masking/Reintroducing Bug |
|-------|----------|---------|----------------------------------|
| `_pickInProgress` | Line 224, 555, 557, 612 | Blocks re-entrant `_pick()` | If first tap's `applyPick()` is deferred (overlay), second tap blocked — but user says first fails, second works |
| `_suggestPanelGrace` 800ms | Lines 238, 318–325 | Keeps panel open after focus loss | Timer + post-frame callbacks create multi-frame window where overlay state flips |
| `_consumeIfDuplicatePick` 400ms | Lines 227–228, 535–544 | De-dupes double pointer events | Fingerprint uses `id␞`label — same item tapped twice within 400ms = ignored |
| `_suppressPanelAfterPick` | Lines 220, 561, 586, 989 | Hides panel after successful pick | Set in `applyPick()`, cleared on controller text change (line 338–343) |
| `_overlayStayOpenUntilDismiss` | Lines 241, 863–865, 931–935 | Keeps overlay open after IME dismiss | Set false in `_listenFocus` (line 377), `_hideSuggestionOverlay` (548), close button (931) |

---

## Debug Trace Plan (Per Prompt)

Add temporary `debugPrint` with timestamps at:

| Event | Location | Suggested Log Format |
|-------|----------|---------------------|
| Focus lost | `_listenFocus` line 395 | `[SUGGEST_TRACE] focusLost hasFocus=false graceArmed=${_suggestPanelGrace}` |
| Grace timer armed | `_armSuggestPanelGraceIfNeeded` line 318 | `[SUGGEST_TRACE] graceArmed timer=800ms rows=${rows.length}` |
| Suggestion tile onTap | `_buildSuggestionTile` line 639 | `[SUGGEST_TRACE] tileTap id=${it.id} label=${it.label}` |
| `_pick` entry | `_pick` line 554 | `[SUGGEST_TRACE] _pickEntry pickInProgress=${_pickInProgress} dupeCheck=${_consumeIfDuplicatePick(it)}` |
| `_consumeIfDuplicatePick` result | Line 538–543 | `[SUGGEST_TRACE] dupeResult fp=${fp} isDupe=${result}` |
| `applyPick` entry | Line 571 | `[SUGGEST_TRACE] applyPickEntry usedOverlay=${usedOverlay}` |
| `onSelected` fire | Line 575 | `[SUGGEST_TRACE] onSelectedFired id=${it.id}` |
| Overlay hide/show | `_hideSuggestionOverlay` 546, `_syncSuggestionOverlay` 856/852 | `[SUGGEST_TRACE] overlayHide/Show isShowing=${_overlayController.isShowing}` |

**Run on real Android device** (not emulator — mobile-only report). Reproduce: tap field, type 2+ chars, tap suggestion row **once**. Record logs for:
- First-tap failure (selection doesn't stick)
- Second-tap success

---

## Suspected Root Cause (Not Confirmed)

**Race between `_overlayController.hide()` in `_pick()` (line 568) and `_syncSuggestionOverlay()` in grace timer's post-frame callback (line 323–324).**

The grace timer's callback runs `setState()` → `_scheduleOverlaySync()` → `_syncSuggestionOverlay()` which re-shows the overlay because `_suggestPanelGrace` is still true. This happens **after** `_pick()` hides it but **before** `applyPick()` completes.

**Why guards don't catch it:**
- `_pickInProgress` blocks *subsequent* `_pick()` calls, not the overlay hide/show race
- `_consumeIfDuplicatePick` only filters same-item taps within 400ms
- `_suppressPanelAfterPick` is set in `applyPick()` (after the race window)

---

## Proposed Fix (Diff Description — Do Not Apply Until Approved)

**Option A: Defer overlay hide until after `applyPick()` completes**
```dart
// In _pick(), move _hideSuggestionOverlay() to applyPick() finally block
void _pick(InlineSearchItem it, {bool keepFocus = true}) {
  // ... existing checks ...
  _pickInProgress = true;
  _cancelSuggestPanelGrace();
  // REMOVE _hideSuggestionOverlay() from here
  
  void applyPick() {
    try {
      // ... existing applyPick body ...
    } finally {
      _pickInProgress = false;
      if (usedOverlay) _hideSuggestionOverlay();  // ← MOVE HERE
    }
  }
  // ... existing scheduling ...
}
```

**Option B: Extend grace timer to cover the full `applyPick()` async window**
```dart
// In _armSuggestPanelGraceIfNeeded, increase timer or make it conditional
// Or: don't start grace timer if _pickInProgress is true
void _armSuggestPanelGraceIfNeeded() {
  if (_pickInProgress) return;  // ← ADD THIS
  // ... rest unchanged
}
```

**Option C: Make overlay hide synchronous with `applyPick()` for overlay mode**
```dart
// In _pick(), for overlay mode, run applyPick synchronously (not post-frame)
// But this risks "inactive element" errors on web (see line 616–622 comment)
```

**Recommended:** Option A — simplest, keeps overlay visible until selection fully applied. Test on device first.

---

## Desktop/Cursor Note

The widget's inline comments (lines 148–150, 234–238) say this is **mobile-specific**: "supplier / broker / item pick felt 'dead' on some devices." Desktop uses same widget but with `suggestionsAsOverlay: true` — test there too, but prioritize physical device repro.

---

## Next Steps

1. **Run debug trace on device** — capture logs for fail/success cases side by side
2. **Identify exact event ordering** for failing case
3. **Confirm which guard** (`_pickInProgress` / grace timer / dupe fingerprint / focus race) swallows first tap
4. **Propose exact fix** as diff in this doc
5. **Wait for approval** before applying