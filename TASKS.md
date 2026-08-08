# TASKS — Living board

Roadmap: [PLAN.md](PLAN.md). Rules: [AGENTS.md](AGENTS.md). Cleanup contract: [docs/ai/16_cleanup_findings.md](docs/ai/16_cleanup_findings.md). Do not invent parallel status docs.

---

## Step A — Docs/README cleanup (active → commit)

| Item | Status | Notes |
|------|--------|-------|
| Author `16_cleanup_findings.md` | done | Approved list on disk |
| Move `docs/ai/09–15` → `docs/ai/archive/` | done | SPECs + diagnostic report |
| Wizard v1 check | done | Only `PurchaseEntryWizardV2`; no delete |
| Trim folder READMEs | done | flutter_app + backend/scripts |
| Delete `scripts/split_hexa_api.py` | done | One-shot splitter |
| Validate + commit Step A only | done | analyze 0 errors; pytest 295 pass / 12 fail pre-existing |

## Step B — Suggestion double-select (next)

| Item | Status | Notes |
|------|--------|-------|
| Fix `PartyInlineSuggestField` dual tap handlers | pending | All pages using shared field |
| Regression test (onSelected once) | pending | Then stop |

---

## Phase 1 — Architecture cleanup (done)

| Item | Status | Notes |
|------|--------|-------|
| Root AGENTS.md + PLAN.md | done | Authoritative contract + roadmap |
| Slim README / TASKS; rule ownership | done | Specialists kept; stockease removed; master → pointer |
| Archive historical docs → `docs/archive/` | done | context/, filesmd/, debugerseniorcode/, UID prompts |
| Confirmed Flutter dead code | done | ~52 orphan files removed |
| Backend dead code + `stock_audit` → `stock_adjustments` | done | Module rename only; routes unchanged |
| Duplicate consolidation | done | Supplier create → Simple; barcode assign helper |
| Large-file / HexaApi splits | done | Unit helpers extracted; HexaApi domain `part` mixins |
| Validation | done | `flutter analyze` 0 errors; tests recorded below |

---

## Recently completed (reference)

| Area | Status | Notes |
|------|--------|-------|
| Design token phases 0–6 | done | Root DESIGN.md + design-quality skill |
| Senior debug blank-UI / sheets | done | Specs under `specs/`; lessons in AGENTS.md |
| UID-001…010 | done | Specs archived under `docs/ai/archive/` |
| Stock blank / stale cells | done | Row patch reconcile + shell visibility |
| Owner FOD waves W0–W6 / P0–P6 | done | Evidence in `docs/debug/`; briefs in `docs/archive/` |
| Local alembic 069/070 | done | Head `070_ai_whatsapp_ops` on laptop DB |
| Stock lag P0 + daily physical logs | done | See `docs/debug/STOCK_LAG_TRACE.md` |

**Note:** Phase 1 completed module rename `stock_audit.py` → `stock_adjustments.py` (routes unchanged).

---

## Production / deploy reminders

| Check | Notes |
|-------|-------|
| Canonical web | `https://purchase-assiastant.vercel.app` |
| API | `api.harisreeagency.online` (Cloudflare Tunnel → Windows FastAPI) |
| Typo hosts | Not our app — do not treat as product bugs |
| PC6 deploy | `git pull` + `alembic upgrade head` on API host separately from laptop DB |

See [docs/debug/OWNER_ADMIN_API_VERIFY.md](docs/debug/OWNER_ADMIN_API_VERIFY.md), [docs/debug/DEPLOY_FIT_CHECK.md](docs/debug/DEPLOY_FIT_CHECK.md).

---

## Open / deferred

| Item | Notes |
|------|-------|
| Home gray / Today-Week sticky void | UX sprint |
| Stock tall rows / detail gray void | UX sprint |
| Commit restore (backup) | 501 until production-copy sign-off |
| WhatsApp / OCR / voice / ERP expansion | PLAN.md P1+ only after approval |
| Backend `catalog.py` router split | Deferred |
| Barcode / API-slowness Phase 1 | After Step B sign-off |
