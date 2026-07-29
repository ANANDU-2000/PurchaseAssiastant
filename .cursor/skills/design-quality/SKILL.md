---
name: design-quality
description: "Enforces design-token discipline and anti-AI-slop UI hygiene on every screen/component the agent touches. Use for any UI work: new screens, edits to existing screens, component creation, or when the user says 'audit', 'redesign', or 'clean up the UI'."
version: 1.0.0
---

# Design Quality

A standing discipline check for UI work. Checklist an agent runs against its own output — not a design generator.

## 0. Find the source of truth first

Before writing or editing any UI code, look for — in this order:
1. Root [`DESIGN.md`](../../../DESIGN.md) — YAML front matter is the token source of truth.
2. Code tokens: `flutter_app/lib/core/design_system/hexa_ds_tokens.dart` + `hexa_colors.dart`.
3. Pack twin: `filesmd/03_DESIGN.md`.
4. If none exist, stop and ask — do not invent colors/fonts/spacing ad hoc.

## 1. Never bypass a token that already exists

- No raw hex / `Color(0x...)` in feature code if a named token covers that role.
- No raw font-size / font-weight if `HexaDsType` covers the role.
- No one-off spacing — use `HexaDsSpace` / `HexaDsWarehouse`.
- New values: add a named token first, then reference it.

## 2. Structural / interaction non-negotiables

- Interactive elements: default, hover (where relevant), focus-visible, pressed, disabled, loading, error, success.
- Min touch ~48px; min readable body ~11–12px (project tokens win).
- No horizontal scroll / two-line CTAs on phone (&lt;600).
- Empty: icon + message + action. Errors: `FriendlyLoadError` / `HexaErrorCard` — never DioException / stack / HTTP codes to users.
- Headings upright — no italic display type.
- Desktop sheets: `showHexaBottomSheet` only. Forms: `DesktopPageShell` max 720. One scroll owner per route.

## 3. Honesty check

- No fabricated metrics unless the user supplied them.
- No fake browser/phone chrome.

## 4. Before finishing any UI task

Self-check this list. If more than one item fails, fix before handing back.
See `filesmd/04_FIX_PLAN.md` / `TASKS.md` for the living sweep board.
