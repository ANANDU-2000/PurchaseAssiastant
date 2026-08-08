# Cleanup findings (approved contract)

**Date:** 2026-08-08  
**Status:** Approved for Step A execution  
**Evidence:** WAVE2 sweep + Phase 1 cleanup + this ask  

Do **not** delete anything not listed here. New suspects → append a row and stop for sign-off.

---

## Keep

| Path | Why |
|------|-----|
| `backend/scripts/archive/**` | Already quarantined; WAVE2: keep under archive |
| `backend/alembic/versions/README.md` | Folder-specific revision-gap notes |
| `data/files/README.md` | Seed JSON field map (folder-specific) |
| `purchase_entry_wizard_v2.dart` | Canonical wizard; **no v1 file exists** |

## Already done (Phase 1 — do not re-delete)

| Action | Notes |
|--------|-------|
| `stock/stock_audit.py` → `stock_adjustments.py` | Module rename; routes unchanged (verify working tree) |
| Flutter orphan widgets/providers (~52) | Confirmed zero refs before delete |
| Backend dead modules (`dashboard.py`, unused services, `enums.py`) | Unregistered / zero imports |
| `legacy_router` removed from `stock_audits.py` | Never mounted |
| Historical docs → `docs/archive/` | context/, filesmd/, debugerseniorcode/, prompts |

## Step A actions (this commit)

| Action | Path | Why |
|--------|------|-----|
| Delete | `scripts/split_hexa_api.py` | One-shot Phase 1 HexaApi splitter; not a product script |
| Move | `docs/ai/09_UID_desktop_fixes_SPEC.md` → `docs/ai/archive/` | Completed UID work |
| Move | `docs/ai/12_UID_006_008_SPEC.md` → `docs/ai/archive/` | Completed |
| Move | `docs/ai/14_UID_009_010_SPEC.md` → `docs/ai/archive/` | Completed |
| Move | `docs/ai/15_diagnostic_report_slowness_refresh.md` → `docs/ai/archive/` | Completed |
| Trim | `flutter_app/README.md` | Flutter-only; drop generic stack already in root README |
| Trim | `backend/scripts/README.md` | Script inventory only; drop stale monthly_payment_reminder pointer |
| Keep | This file (`docs/ai/16_cleanup_findings.md`) | Living cleanup contract |

## Wizard v1 resolution

**Verified:** Only `PurchaseEntryWizardV2` exists under `flutter_app/lib/features/purchase/presentation/`.  
`app_router.dart` mounts `PurchaseEntryWizardV2` only. No `purchase_entry_wizard.dart` / v1 class.  
**Action:** No delete (nothing leftover to remove). Optional rename of `*_v2*` is out of scope.

## Explicit non-goals

- Extra dead-code sweeps beyond this list  
- Provider merges (WAVE2: none flagged as true dupes)  
- Barcode / API-slowness / WhatsApp / OCR
