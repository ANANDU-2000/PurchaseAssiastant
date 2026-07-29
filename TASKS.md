# TASKS — Living board

## Design Fix Master Board

Living checklist from `filesmd/04_FIX_PLAN.md`. One phase at a time.

| Phase | Status | Notes |
|-------|--------|-------|
| 0 DESIGN.md sync + device contract | done | Root `DESIGN.md`; breakpoints match `hexa_responsive` |
| 1 design-quality skill + rule | done | `.cursor/skills/design-quality`, `.cursor/rules/design-quality.mdc` |
| 3 scaffolding | done | Removed `features/dashboard`; kept `features/item` + comment |
| 2 stock tokens | done | Sweep via `scripts/token_sweep_colors.py` + new HexaColors tokens |
| 2 purchase tokens | done | Same sweep; `flutter analyze` clean of errors |
| 4 reports/home/catalog/auth | done | Included in module sweep |
| 5 contacts/barcode/staff | done | Included in module sweep (brand colors only) |
| 6 visual 390/820/1440 + tests | done | `device_contract_test.dart` + existing sheet/shell tests |

Remaining `Color(0x…)` literals are sparse one-offs (charts, overlays, rare chips) — continue opportunistically on touch, not a blind replace.

## Senior Debug — Bugs First

From plan `senior_debug_bugs_first`. Specs: `specs/desktop-blank-ui.md`. Tooling: root `AGENTS.md`, `.cursor/skills/code-review`.

| Phase | Status | Notes |
|-------|--------|-------|
| A Install AGENTS + code-review + specs | done | Lessons from real blank-sheet / host bugs |
| B1 Nested `HexaResponsiveSheetViewport` | done | low_stock_approval + opening stock bulk dialog |
| B2 `compact:false` height risks | done | catalog move + bulk barcode preview → compact/true |
| B3 Verify trade list vs KPI / reports height | done | No code change — intentional empty off History; reports already stretch+height |
| C Hardcode hotspots | done | reports_stock_status, stock intel, purchase entry sheet, purchase home + HexaColors tokens |
| D Code-review vs git diff | done | Spec IDs checked; sheet tests green; Ready to commit (see AGENTS) |
| Follow-up: reports filter → Hexa sheet | done | Mobile left `showModalBottomSheet`/`DraggableScrollableSheet`; now `showHexaBottomSheet` + height |

## UID Desktop Fixes

Spec: `docs/ai/09_UID_desktop_fixes_SPEC.md`

| ID | Status | Notes |
|----|--------|-------|
| UID-001 | done | HTML splash only after bootstrap/HexaApp frame (`main.dart`) |
| UID-002 | done | Relabeled chip vs KPI (Below reorder vs Need attention) |
| UID-003 | done | Truck badge qty · days with HexaDsSpace.xs |
| UID-004 | done | Left-anchored desktop actions dialog + black54 barrier |
| UID-005 | done | Subtitle "System stock · N" |

## UID-006…008

Spec: `docs/ai/12_UID_006_008_SPEC.md`

| ID | Status | Notes |
|----|--------|-------|
| UID-006 | done | System snackbar floating + clear copy |
| UID-007 | done | Verify patch fields + harden alias/fallback |
| UID-008 | done | AppFormRow on stock sheet + 3 wizard steps |

## UID-009…010

Spec: `docs/ai/14_UID_009_010_SPEC.md`  
Report: `docs/ai/15_diagnostic_report_slowness_refresh.md`

| ID | Status | Notes |
|----|--------|-------|
| UID-009 | done | In-flight guard + reloadHexaApp kept (ErrorWidget) |
| UID-010 | done | Foreground reconnecting via apiDegraded; Task C skipped |

Do not invent parallel status docs.
