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

## Production validation checklist (2026-07-29)

**Canonical URL only:** `https://purchase-assiastant.vercel.app`  
(look for **assiastant** — extra **a** after “assi”)

| Check | Status | Notes |
|-------|--------|-------|
| Vercel prod deploy `4eab5da`+ | done | Project `purchase-assiastant` READY |
| API `api.harisreeagency.online` | done | Cloudflare Tunnel → Windows Server FastAPI |
| UID-001…010 code on main | done | Pushed |
| `purchase-assistant…/stock` | **user typo** | Different site → **404** — not our app |
| `purchase-assiatant…` (missing s) | **user typo** | Not alias of this project → blank/wrong |
| Redirects in `vercel.json` for typo hosts | code ready | **Only work after** those hosts are added as domains on project `purchase-assiastant` in Vercel |
| Home gray / Today-Week sticky void | **not fixed** | Out of UID scope — need UX sprint |
| Stock tall rows / detail gray void | **not fixed** | Out of UID scope — need UX sprint |

## Stock blank / stale cells (2026-07-29)

| Fix | Status | Notes |
|-----|--------|-------|
| Chain-sheet race (actions → physical/system) | done | `stock_row_actions` + `low_stock_item_detail_sheet` pop-with-result, open next after await |
| `/stock` white `SizedBox.shrink` | done | `_stockShellTabVisible` mirrors home (shell index + path) |
| Optimistic SYS/PHYS cells wiped | done | `reconcileStockListRowPatches` only clears when server matches or newer `stock_version` |
| Tests | done | `stock_list_row_patch_test` + `stock_row_actions_test` |

| Owner action (required for typo URLs to stop 404/blank):**  
~~Vercel Domains alias~~ — **paused**: wrong Hobby project still holds `purchase-assistant.vercel.app`.  
**Done via MCP (2026-07-29):** Render `CORS_ORIGINS`/`ADMIN_URL` updated for `purchase-assiastant` + typo hosts; Vercel prod = `4925d8b` on `prj_ubxhNkOxAG2tM7o00u7ZBEjZ0VMM`.

Do not invent parallel status docs.

## Owner-critical FOD (2026-08-08)

Program: `context/` briefs — one wave at a time. HEAD at start: `fffc710`.

| Wave | Status | Evidence |
|------|--------|----------|
| W0 Baseline | done | Live `GET /health` → 200 (`app_env=development`); Vercel HTML has `api.harisreeagency.online`, no onrender; alembic head `068` then added `069_owner_ops_tables`; no tracked `.env` secrets |
| W1 Live smoke | done | `smoke_production_api` initially **403** without UA (Cloudflare); fixed script UA → **PASS** health/live, ready, CORS, preflight. Schema version field null in ready body but `schema_ok` true |
| W2 Deadcode map | done | Report: `docs/debug/WAVE2_DEADCODE_SWEEP.md` — read-only; renames/deletes **blocked** pending sign-off |
| W3 Backup/restore | done | `backup_logs` + nightly 02:00 IST job; `POST …/exports/backup/run`, `GET …/backup/logs`, dry-run restore; **commit restore = 501** until production-copy sign-off |
| W4 API credentials | done | `provider_credentials` encrypted; `GET/PUT …/settings/credentials`; Flutter `OwnerCredentialsPage` |
| W5–6 Staff + owner CC | done | `staff_tasks` + endpoints; `GET …/owner/dashboard`; Flutter tasks + command center |
| UX Purchases pane | done | `PurchaseDesktopDetailPane` uses `DesktopDetailPaneScaffold` |
| UX Reports pane | done | Overview desktop uses `DesktopDetailPaneScaffold` + stretch Row (same Stock/Purchase pattern); mobile unchanged |
| P0 Ship 1444692 | done | Pushed owner-ops; smoke PASS 2026-08-08; **operator:** `alembic upgrade head` on Windows API for 069 |
| P1 UX Reports | done | Overview desktop `DesktopDetailPaneScaffold`; blank-safe stretch Row retained |
| P2 Partial gaps | done | `resolve_key` in `llm_failover`; backup logs/dry-run UI; staff accept/complete/create; dashboard damage/AI/WA + TTL |
| P3 Dedup rename | done | `stock_audit.py` → `stock_adjustments.py` (routes unchanged) |
| P4 OpenRouter | done | `run_tiered_failover` + `ai_usage_logs` (070); OCR AI path via `extract_item_rows_via_ai`; `AI_FORCE_TIER2_ONLY` |
| P5 WhatsApp PO | done | `whatsapp_delivery_logs`; send on lifecycle `approved`; owner resend; creds from 07 |
| P6 Fit-check | done | `docs/debug/DEPLOY_FIT_CHECK.md` |
| Phase A RBAC+creds | done | owner/admin gate; phone_number_id; Graph PDF document send; media OCR `use_ai` |
| Phase B API verify | done | health head 070; `check_env_keys` PASS; smoke PASS; `docs/debug/OWNER_ADMIN_API_VERIFY.md` |
| Desktop UX C1–C4 | done | Home Wrap alerts + off-tab canvas; Stock/Purchase fill gutters; Reports ≤3 cols; Settings ListView expand |
| Local alembic 069/070 | done | Cursor PC: `localhost:5433/harisree_db` → `070_ai_whatsapp_ops`; 069/070 idempotent; unit tests 13 PASS |
| Stock lag P0 | done | Activity 15s timeout + shell audit seed; tab-return bundle-only; physical snackbar; Dio storm monitor; health expect **069** |

**Deploy note:** PC6 API host must `git pull` + `alembic upgrade head` separately (laptop DB ≠ server DB). See `docs/debug/OWNER_ADMIN_API_VERIFY.md` and `docs/debug/STOCK_LAG_TRACE.md`.
