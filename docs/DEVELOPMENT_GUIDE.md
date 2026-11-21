# Development Guide — AI-assisted workflow

Status as of 2026-11-21. "Verified" means exercised in a real session; everything else is a plan.

## 1. Integration status

| Integration | Status | Evidence |
|---|---|---|
| Claude Code | Verified | v2.1.325 |
| Graphify CLI | Verified | graph built, 0 API cost |
| Graphify MCP | Verified | JSON-RPC handshake lists 12 tools; needs `graphifyy[sql,mcp]` extras |
| TestSprite MCP | Registered; connects when `TESTSPRITE_API_KEY` is in the process env | Tools not yet inspected; **0 credits used** |
| GitHub CLI | **Not authenticated** | `gh auth login` required |
| Namecheap MCP | **Verified, correct account** | Registrant is the owner; `harisreeagency.online` registered, expires 2027-08-07, nameservers = Cloudflare (`rene` / `coraline`). Namecheap cannot edit DNS (zone is on Cloudflare). |
| Cloudflare MCP (Workers Bindings, deprecated) | Connected, **cannot verify zone/DNS/tunnel** | Only Workers/KV/D1/R2/Hyperdrive tools; `workers_list` returned 0. Zone status needs the Cloudflare API MCP (`https://mcp.cloudflare.com/mcp`). |
| Vercel MCP (claude.ai connector) | Connected, **wrong account** | Signed in as the SBSOL account; projects are `proimprint-*` and `sbsol-ai-tracker`. No `purchase-assiastant` project. Do not use for this app until reconnected to the right account. |
| Render MCP (claude.ai connector) | Connected, **wrong account** | Workspace "ANANDU SBSOL TESTING": ProImprint services and a suspended `proai_catalog` DB. No `my-purchases-api` or `harisree_db`. The project's own `.mcp.json` (`render-harisree`, `RENDER_API_KEY`) is the intended path and is **not yet verified**. |
| Browser (Claude in Chrome) | Verified | Tab group created in this session |
| Ralph Loop | Present, idle | `ralph/` + `loop_auto.sh`; no loop process running. The script runs with `--dangerously-skip-permissions`: start only in its own worktree, never alongside another agent. |
| Windows Server deploy | Draft only (PR #9, unrun) | |

Secrets rule: never paste keys into chat or files. GitHub → `gh auth login` (browser). TestSprite → user env var `TESTSPRITE_API_KEY`; MCP config references `${TESTSPRITE_API_KEY}`. A key that has been pasted in a conversation must be rotated.

## 2. Worktree ownership (one agent per file set)

| Worktree / branch | Owner | Purpose |
|---|---|---|
| main checkout `ralph/local` (726 dirty files) | **Human only — do not touch** | Original work |
| `hexa-worktrees/fix-ci-recovery` · `fix/ci-recovery` | CI-recovery agent (one session) | PR #8 |
| `hexa-worktrees/windows-deploy` · `feat/windows-deploy` | DevOps agent | PR #9 |
| `hexa-worktrees/ai-docs` · `docs/ai-environment` | Docs agent | This documentation |
| `hexa-worktrees/baseline-main` | Read-only reference | Comparison |
| New feature work | `git worktree add ../hexa-worktrees/<name> -b feat/<name> origin/main` | One per feature |
| Graphify analysis | Read-only against any worktree's `graphify-out/` | |

Never run two agents/Ralph loops in the same worktree. On 2026-11-21 a second session was observed rewriting Flutter tests in `fix-ci-recovery` while another ran the suite; results of that overlap are unreliable.
Banned: `git reset --hard`, `git clean -fd`, force-push, auto-merge, production deploy/migration without explicit human approval.

## 3. Agent roles

| Agent | Owns | Must not |
|---|---|---|
| CTO / PM | Task breakdown, Graphify impact analysis, PR descriptions, approvals queue | Edit code |
| Backend | `backend/app/**`, `backend/tests/**` | Touch Flutter or migrations |
| Flutter | `flutter_app/**` | Touch backend |
| Database | `backend/alembic/**`, `backend/sql/**`; migrations are written and reviewed, **never run against production** | Run prod migrations |
| QA / TestSprite | E2E plans and test results; reports failures | Change app code to pass tests |
| DevOps | `.github/**`, `deploy/**`, `scripts/**`, `vercel.json` | Deploy without approval |
| Security | Read-only review of auth, permissions, secrets, dependencies | Merge |

Coordination: CTO agent keeps a task list; each task names its worktree and file globs; overlapping globs are serialised.

## 4. Pipeline (feature → production)

```
Request → Graphify impact analysis → feature worktree/branch → implement
 → flutter analyze → targeted tests → full suites → local commit
 → human OK to push → GitHub PR (CI) → Vercel preview (automatic per PR)
 → TestSprite E2E on the preview (credit-approved) → human review
 → human merges → production deploy (Vercel from main; backend per DEPLOYMENT.md)
 → post-deploy smoke (/health/ready) → rollback plan ready
```

Local gates (run from the relevant worktree):

| Area | Command |
|---|---|
| Flutter static | `cd flutter_app && flutter analyze` |
| Flutter tests | `flutter test` |
| Backend tests | `cd backend && python -m pytest -q` (Python 3.12 venv; 3.14 lacks wheels for some deps) |
| Graph refresh | `graphify update .` |

Vercel preview deployments are confirmed: PR #8 shows a passing "Vercel" check linking to project `purchase-assiastant` under team `anandukrishnapa2000-gmailcoms-projects`. The claude.ai Vercel connector is not yet connected to that team.

## 5. TestSprite E2E plan (no credits spent yet)

Target: a Vercel preview or local build against a seeded **non-production** backend. Never run against production data.

| # | Scenario | Roles | Key assertions |
|---|---|---|---|
| 1 | Login / logout / bad password | all | Redirect, session restored on refresh |
| 2 | Owner dashboard | owner | KPIs load, no section error states |
| 3 | Staff dashboard | staff | Floor KPIs, no financial figures (redaction) |
| 4 | Stock: physical count save | owner, staff | Column updates immediately; stale-version conflict shows prompt, never silent overwrite |
| 5 | Purchase creation (wizard) | owner, staff | Totals match backend; line units valid; duplicate catalog line rejected |
| 6 | Barcode scan | staff | Known item → summary card (System / Physical / Last Purchase); unknown → clear message |
| 7 | Supplier management | owner | Create via wizard, detail page, edit |
| 8 | Reports | owner/manager | 4 primary tabs, filters, export; staff blocked |
| 9 | Permissions matrix | all roles | Each key in `permissions.py` enforced in UI **and** API |
| 10 | AI assistant / OCR parse | owner | Needs LLM keys; consumes paid provider tokens — run last |

Before running: inspect TestSprite tools in a fresh session, ask TestSprite for its credit cost for this plan, present the number to the human, and wait for approval. Start with scenario 1 only to measure per-test cost.

## 6. Infrastructure readiness

| Piece | State | Gap |
|---|---|---|
| GitHub Actions | CI, db-backup, smoke workflows exist | CI red on PR #8/#9; keepalive workflow referenced in docs is missing |
| Vercel | Config present (`vercel.json`) | Preview/Git integration unverified |
| Render | Documented production API + Postgres | Not inspected this session |
| Windows Server 2022 + Cloudflare Tunnel | Scripts on `feat/windows-deploy` (install, deploy, rollback, health monitor, Postgres backup) | Unrun, draft; dead-host CI guard needs deliberate update at cutover |
| Cloudflare / Namecheap | MCP reachable | DNS for the new API host not verified |
| PostgreSQL | Alembic migrations; weekly `pg_dump` artifact | Restore not rehearsed |

## 7. Monthly cost model (no prices invented)

Prices change; the "check" column says where to confirm. Fill the amounts from your own invoices.

| Item | Free tier? | Cost driver | Check |
|---|---|---|---|
| Claude Code / models | Included in your plan up to its limits | Tokens/usage beyond plan | Anthropic console / plan page |
| Graphify (local AST) | **Free, open source** | None for AST mode; optional LLM semantic mode is paid per token — **leave off** | n/a |
| TestSprite | Free credits (screenshot showed 150 remaining) | Credits per test run; paid plans beyond | TestSprite billing |
| GitHub | Free for this usage (public repo, Actions minutes) | Private repo Actions minutes if made private | GitHub billing |
| Vercel | Hobby tier exists | Builds, bandwidth; team/commercial use may require paid plan | Vercel billing |
| Render | Free tier sleeps (keep-alive was used to avoid it) | Always-on web service + Postgres are paid | Render billing |
| Windows Server host | No | VM/hardware, Windows licence, power | Hosting invoice |
| Cloudflare Tunnel / DNS | Free tier available | Paid only for advanced features | Cloudflare plan |
| Namecheap | No | Domain renewal | Namecheap account |
| LLM providers used by the app (OpenAI/Gemini/Groq) | Varies | Per-token usage from the assistant/OCR; logged by `log_ai_usage` | Provider dashboards |
| Backups | Actions artifact (free within limits) | Off-site storage if added | GitHub / storage provider |
| Monitoring | Scripts only (`health-monitor.ps1`) | Hosted monitoring if added | n/a |

Controls: no paid TestSprite or LLM run without an estimate and approval; keep Graphify in AST mode.

## 8. Blockers

1. `gh auth login` (human, browser).
2. Rotate the exposed GitHub token and TestSprite key; set the new env var; open a fresh session.
3. Quiesce the second session in `fix-ci-recovery`, then re-run full Flutter tests (6 failures were seen, in files being edited).
4. PR #8/#9 CI logs review.
5. Decisions listed in `AI_ARCHITECTURE.md` §7.
