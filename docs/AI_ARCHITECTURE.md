# AI Architecture Report — HEXA Purchase Assistant

Generated 2026-11-21 from the Graphify graph of `fix/ci-recovery` @ `47b8040` (graph is AST-only, built locally, zero API cost) plus direct reading of the code. Anything not verified is marked **UNVERIFIED**.

## 1. Corpus and graph

| Metric | Value |
|---|---|
| Files analysed | 1,348 (~757k words) |
| Nodes / edges / communities | 19,658 / 36,416 / 749 |
| Extraction | 99% EXTRACTED, 1% INFERRED (402 edges, avg confidence 0.94) |
| Import cycles | **None detected** |
| Isolated symbols (≤1 edge) | 9,150 — mostly private Flutter state fields; not a defect by itself |

Re-run `graphify update .` after code changes (no cost). Graph freshness is pinned to a commit in `GRAPH_REPORT.md`.

## 2. System shape

```
Flutter app (web on Vercel, also Android/desktop)  ──HTTPS──▶  FastAPI (backend/app)  ──▶  PostgreSQL
 flutter_app/lib/{core,features}                              routers/ → services/ → models/
```

- **Frontend** — Riverpod + go_router. Features: auth, barcode, broker, catalog, contacts, home, item, notifications, operations, purchase, reports, search, settings, shell, splash, staff, stock, supplier. All API access flows through `core/api/hexa_api*.dart` (`hexaApiProvider`, 193 edges).
- **Backend** — routers: auth, me, users, catalog, contacts, trade_purchases, stock/* (list, detail, adjustments, barcode, ops), stock_audits, reports_trade, report_views, exports, damage_reports, notifications, realtime, search, owner_ops, operations, media, public_items, client_errors, health. Business logic lives in `services/` (e.g. `trade_purchase_service`, `stock_movement_service`, `trade_query`).
- **Database** — SQLAlchemy models under `backend/app/models`; Alembic migrations; PostgreSQL in production, SQLite in CI smoke tests.

## 3. Core abstractions (Graphify god nodes)

| Node | Edges | Meaning / risk |
|---|---|---|
| `sessionProvider` | 304 | Auth/session state read by most of the UI. A change here ripples everywhere. |
| `get_db()` | 242 | Every DB-touching route. |
| `Membership` | 234 | Tenant + role link; the unit of authorization. |
| `hexaApiProvider` | 193 | Single Flutter→backend gateway. |
| `require_membership()` | 166 | Tenant-scoping dependency on routes. |
| `get_current_user()` | 106 | JWT identity. |
| `CatalogItem` | 100 | Central entity (stock, purchases, barcodes). |

**Rule:** before editing any of these, run `get_pr_impact` / `get_neighbors` (Graphify MCP) and list affected files in the PR.

## 4. Authentication and permission boundaries

- Identity: JWT (`services/jwt_tokens.py`, `auth_login.py`, `google_oauth.py`); `deps.get_current_user`.
- Tenancy: `deps.require_membership` scopes every request to a business.
- Authorization: `deps.require_permission(key)`; keys in `services/permissions.py`:
  `stock_edit, purchase_create, purchase_edit, barcode_print, reports_access, export_access, user_manage, delete_access, analytics_access`.

| Role | Differences from full access |
|---|---|
| owner, admin | all keys true |
| manager | no `user_manage`, no `delete_access` |
| staff | no `purchase_edit`, `reports_access`, `export_access`, `user_manage`, `delete_access`, `analytics_access` |

Per-membership overrides merge over the role template (`effective_permissions`). Staff financial redaction is covered by backend tests (`test_staff_financial_redaction.py`).

## 5. Business workflows (where the code lives)

| Workflow | Backend | Frontend |
|---|---|---|
| Purchase entry | `routers/trade_purchases.py`, `services/trade_purchase_service.py`, `trade_query.py`, `line_totals_service.py` | `features/purchase/*` (wizard, fast-items), `core/calc_engine.dart`, `core/purchase/*` |
| Stock & optimistic locking | `services/stock_movement_service.py` (`stock_version`, `StaleStockVersionError`), `routers/stock/*` | `core/stock/stock_version_retry.dart`, `features/stock/*` |
| Barcode | `routers/stock/stock_barcode.py` | `features/barcode/*` |
| Reports | `routers/reports_trade.py`, `report_views.py` | `features/reports/*` |
| Notifications / low stock | `services/low_stock_*`, `notification_emitter.py` | `core/notifications`, `features/notifications` |
| Staff tasks / audits | `services/staff_tasks.py`, `stock_audit_service.py` | `features/staff` |

Stock write contract: clients send `stock_version`; mismatch → 409 `STALE_STOCK_VERSION`. `force=true` bypasses the check and must only be sent after explicit user confirmation (fixed in commit `3cdabea` — the client previously auto-forced the final retry).

## 6. External integrations

| Integration | Where | Notes |
|---|---|---|
| LLM providers (OpenAI, Gemini, Groq) | `services/llm_failover.py`, `llm_intent.py`, `ocr_parser.py`, `provider_credentials.py` | Ordered/tiered failover; usage logged via `log_ai_usage`. Keys via env (`OPENAI_API_KEY`, `GROQ_API_KEY`, Gemini). Paid per use. |
| Google OAuth | `services/google_oauth.py` | |
| Vercel | `vercel.json`, `scripts/vercel-flutter-build.sh` | Builds Flutter web, pins 3.41.6. |
| Render | `DEPLOYMENT.md` | Current production API `my-purchases-api.onrender.com`, Render Postgres. |
| Windows Server + Cloudflare Tunnel | branch `feat/windows-deploy` (`deploy/windows/*`, deploy/rollback workflows) | **Planned, draft PR #9, unrun.** |

## 7. Findings requiring a human decision

1. **Docs vs. CI drift.** `DEPLOYMENT.md` lists `render-keepalive.yml`; that workflow does not exist in `.github/workflows/` (present: `ci.yml`, `db-backup.yml`, `post-deploy-smoke.yml`, `production-smoke.yml`).
2. **Two "canonical" production stories.** CI fails the build if the Windows-tunnel host (`api.harisreeagency.online`) appears in shipped code, while PR #9 builds exactly that migration. The guard script will need an intentional update when the cutover is approved.
3. **Scan card supplier.** An old test expected the supplier name on the barcode scan card; the card never rendered it. Decide whether that is a wanted feature.
4. **PR #8 / #9 CI is red.** Backend pytest passes locally (327), so remaining CI failures need a fresh log review once the recovery worktree is quiescent.
5. **Graph noise.** Markdown planning files (`ralph/`, `uiux context/`, `AGENTS.md`) appear as high-degree nodes ("ORDERED UX TASKS…" has 152 edges). Add a `.graphifyignore` for them to keep code analysis clean (proposal; not applied).

## 8. Known limits of this report

- Graph captures static structure; runtime behaviour, DB contents and production config are **not** covered.
- SQL files are included (parser extra installed), but 9 SQL scripts yielded no symbols.
- Nothing here was exercised in production.
