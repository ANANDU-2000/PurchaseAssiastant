---
name: Harisree Warehouse
colors:
  primary: "#0E4F46"
  secondary: "#065F4F"
  accent: "#159A8A"
  gold: "#D4AF37"
  background: "#F7F9F6"
  card: "#FFFFFF"
  border: "#E2E8E6"
  textPrimary: "#0F172A"
  textBody: "#475569"
  textMuted: "#64748B"
  success: "#059669"
  error: "#DC2626"
  warning: "#F0A500"
typography:
  h1:
    fontFamily: Plus Jakarta Sans
    fontWeight: 700
    fontSize: 1.375rem
  h2:
    fontFamily: Plus Jakarta Sans
    fontWeight: 600
    fontSize: 1.125rem
  body:
    fontFamily: Plus Jakarta Sans
    fontWeight: 400
    fontSize: 0.875rem
  label:
    fontFamily: Plus Jakarta Sans
    fontWeight: 600
    fontSize: 0.75rem
  metric:
    fontFamily: Plus Jakarta Sans
    fontWeight: 900
    fontSize: 1.375rem
rounded:
  sm: 10px
  md: 12px
  lg: 16px
  xl: 20px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
breakpoints:
  # Aligned with flutter_app/lib/core/design_system/hexa_responsive.dart (code = truth)
  compactPhone: 360px
  phoneMax: 599px
  tabletMin: 600px
  navigationRailLabels: 900px
  desktopMin: 1024px
  ultraWideMin: 1600px
  maxContentWidth: 1180px
  maxHomeContentWidth: 1440px
  maxFormWidth: 720px
  maxSheetWidth: 640px
  minTouchTarget: 48px
  minReadableFont: 11px
---

## Overview

**Premium green + gold fintech-warehouse hybrid.** The palette reads as a serious financial /
ERP tool (deep teal-green primary, generous white space, restrained gold accent for
profit/premium moments) rather than a generic Material app. Plus Jakarta Sans throughout, at a
fairly heavy weight scale (buttons and metrics go all the way to w900) — the app leans confident
and dense, appropriate for warehouse staff scanning numbers quickly, not a consumer social app.

This file was extracted from the app's actual source tokens (`core/design_system/hexa_ds_tokens.dart`
and `core/theme/hexa_colors.dart`) — it describes what's already built, not a new direction. Its
purpose is to give any coding agent (Cursor, Claude Code, etc.) a portable, framework-agnostic
description of the system so a screen built from a prompt alone still lands on-brand.

Human-facing twin: `filesmd/03_DESIGN.md`. Enforceable agent checklist:
`.cursor/skills/design-quality/SKILL.md`.

## Colors

- **Primary (#0E4F46):** Deep teal-green. Primary buttons, headers, brand moments. Token: `HexaColors.brandPrimary`.
- **Secondary (#065F4F):** Slightly deeper green, used for gradient stops and hover states.
- **Accent (#159A8A):** Brighter teal — the interactive/CTA driver, gradient end-stop.
- **Gold (#D4AF37):** Reserved for profit/premium badges and highlight gradients. Sparingly —
  it's a signal color, not a decoration.
- **Background (#F7F9F6):** Warm off-white canvas. Token: `HexaColors.brandBackground`.
- **Card (#FFFFFF):** Pure white for elevated surfaces.
- **Success/Error/Warning:** Semantic greens/reds/ambers — kept separate from the brand green.
  Prefer `HexaDsColors.success` / `HexaDsColors.error` / `HexaColors.warning`.

## Typography

Plus Jakarta Sans is the only typeface. Use `HexaDsType.*` — do not invent inline `TextStyle(fontSize: …)`.

## Spacing & layout

8px grid throughout (`HexaDsSpace`). Page gutter 24px, section gaps 24px, block gaps 16px,
inline gaps 8px. Warehouse-dense screens use `HexaDsWarehouse` (12px card padding, 10px gaps,
52px min list-row height, 48px min touch). Do not blend dashboard-spacious and warehouse-dense
on one screen.

## Radius & elevation

Minimum 12px radius (`HexaDsRadii`). Cards up to 20px. Soft layered shadows, not hard drops.

## Breakpoints (device contract)

| Viewport | Width | Expectation |
|----------|-------|-------------|
| Compact phone | ≤360 | Single column; stack forms |
| Phone | &lt;600 | Bottom nav; `AppFormRow` stacks |
| Tablet | 600–1023 | Compact rail; `AppFormRow` side-by-side |
| Rail labels | ≥900 | Optional extended rail labels |
| Desktop | ≥1024 | Master-detail; forms ≤720 (`DesktopPageShell`); sheets via `showHexaBottomSheet` |
| Ultra | ≥1600 | More gutters only — never stretch content edge-to-edge |

Code source of truth: `kTabletMin` / `kDesktopMin` / `kUltraWideMin` in `hexa_responsive.dart`.

## How to use this file

Before building or editing a screen: read this file, then use named tokens only. If a new value is
needed, add it to `hexa_ds_tokens.dart` / `hexa_colors.dart` first, then reference it.
