# Recovery Status

Last updated 2026-11-21. "Verified" = exercised in a real session. Nothing here has been pushed.

## 1. Integration verification

| Integration | State | Evidence / next action |
|---|---|---|
| Graphify CLI + MCP | Verified | JSON-RPC handshake lists 12 tools; graph readable (19,658 nodes). Requires `graphifyy[sql,mcp]`. |
| Browser (Claude in Chrome) | Verified | Tab group created. |
| Namecheap | Verified, correct account | `harisreeagency.online` registered to 2027-08-07; registrant is the owner; nameservers `rene.ns.cloudflare.com`, `coraline.ns.cloudflare.com`. DNS cannot be edited at Namecheap (zone is on Cloudflare). |
| GitHub CLI | **Verified** | Browser device-flow login as `ANANDU-2000` (keyring, HTTPS; scopes `repo`, `read:org`, `gist`). Repo permission: ADMIN. PR #8 latest CI run: success. PR #9 CI: failing in "Alembic migrations (SQLite smoke)" (`sqlite3.ProgrammingError: You can only execute one statement at a time`) — same failure PR #8 fixed; PR #9 likely needs the #8 fixes (rebase after #8 merges, with approval). Previously exposed PAT must still be revoked by the owner. |
| TestSprite MCP | **Verified** (handshake in a child process fed from the user-level env var) | Server `testsprite-mcp-server` 0.0.48, 8 tools: `bootstrap`, `generate_code_summary`, `generate_standardized_prd`, `generate_frontend_test_plan`, `generate_backend_test_plan`, `generate_code_and_execute`, `open_test_result_dashboard`, `check_account_info`. Account: **Free plan, 150 credits, 0 consumed**. Per-test credit cost is not published by the tools; measure with one test before any batch. Note: the running Claude Code session itself still lacks the variable, so its in-session MCP shows "missing env" until Claude Code is restarted. The key was pasted into chat earlier and should be rotated. |
| Cloudflare Workers MCP (claude.ai) | Partial | Workers/KV/D1/R2/Hyperdrive only; 0 workers. Cannot see zones, DNS, tunnels. |
| Cloudflare API MCP | **Added, needs sign-in** | Registered at user scope (`cloudflare-api` → `https://mcp.cloudflare.com/mcp`); status "Needs authentication". OAuth must be completed by the owner in an interactive session (`/mcp`). Zone/DNS/Tunnel checks are pending on this. |
| Vercel (claude.ai connector) | **Wrong account** | Signed in as the SBSOL account; projects `proimprint-videomaker`, `proimprint-ai`, `sbsol-ai-tracker`; no `purchase-assiastant`. The real project is `purchase-assiastant` under the Vercel team `anandukrishnapa2000-gmailcoms-projects` (seen in the PR #8 "Vercel" check URL; a third account, neither SBSOL nor the git/Namecheap one). Reconnect the connector to that account. Git-integration preview deployments are confirmed working (PR #8 shows a passing Vercel check). |
| Render (claude.ai connector) | **Wrong account** | Workspace "ANANDU SBSOL TESTING"; ProImprint services; suspended `proai_catalog` DB; no `my-purchases-api` / `harisree_db`. Reconnect with the Harisree-owning account. Project-local `render-harisree` MCP (`RENDER_API_KEY`) is unverified; a direct API call with that key was blocked by the permission classifier and not retried. |
| PRO_AGENT connector | Ignored | Unrelated; HTTP 503. |
| Ralph Loop | Controlled runner built, **not started** | Original `loop_auto.sh` is unsafe (see §3). A guard-railed replacement exists in worktree `hexa-worktrees/ralph-controlled` (branch `ralph/controlled`, 2 local commits, not pushed). All guards tested; `claude` was never launched. |

## 2. Code state (nothing pushed)

| Branch / worktree | Commits |
|---|---|
| `fix/ci-recovery` (`hexa-worktrees/fix-ci-recovery`) | `3cdabea` stale-stock no-auto-force fix + stale scan-card test fix. Another session was concurrently editing Flutter tests in this worktree; its uncommitted changes were left untouched. |
| `docs/ai-environment` (`hexa-worktrees/ai-docs`) | Documentation only (four files under `docs/`), based on `main`; delivered as a docs-only PR |
| `ralph/local` (main checkout) | Untouched; 726 dirty files preserved |

Tests: backend pytest 327 passed; `flutter analyze` clean; full Flutter suite had ~6 failures in files being rewritten by the other session — re-run once that session is stopped.

### PR status (2026-11-21)

| PR | State |
|---|---|
| #8 `fix/ci-recovery` | Open, mergeable, merge state CLEAN, all 8 checks pass on head `35aef97` (backend pytest, backend on PostgreSQL, Flutter analyze/test, SSOT smoke, web build, dead-host guard, Vercel). 84 files: 26 Alembic edits (24 are SQLite-only early returns, PostgreSQL behaviour unchanged; 043 now executes its two `CREATE INDEX IF NOT EXISTS` statements one by one), Flutter/backend tests, 13 Flutter lib and 5 backend app files (incl. no-auto-force stock retry and a password-policy fix with tests). Ready for owner review; **not merged**. |
| #9 `feat/windows-deploy` | Draft; waits for #8 to merge, then rebase (needs approval). |
| #10 `docs/ai-environment` | Docs-only (four files), opened for review. |

## 3. Ralph Loop — controlled execution plan

### What `loop_auto.sh` does today (read from the script)
- every round: `git pull --rebase origin main`, then `claude -p … --dangerously-skip-permissions --max-turns 150`, then **`git push origin HEAD:main`**;
- defaults `APP_URL`/`API_URL` to the production Vercel/Render hosts and waits on `/health/ready` there; QA specs under `ralph/qa/` use `QA_EMAIL`/`QA_PASSWORD`;
- stops on `ralph/STOP`, "ALL DONE", max rounds or 4 stalled rounds.

### Why it must change before use
1. It pushes straight to `main` — contradicts "human approval before merge/deploy".
2. Full permission bypass with shell access.
3. QA targets production, with real credentials in `ralph/qa/.env`.
4. It would run in the main checkout that holds the 726 uncommitted files.

### Implemented: `ralph/loop_controlled.sh` + `ralph/PROMPT_CONTROLLED.md` (worktree `ralph-controlled`)
The original prompt `PROMPT_AUTO.md` also instructs "push main, wait for Vercel + Render deploy, re-run prod QA", so a separate prompt was written too. Guards verified by running the script with inputs that must be refused: rounds above the cap of 5, non-numeric rounds, any `onrender.com` / `vercel.app` / `harisreeagency.online` target, a non-`ralph/*` branch, and a dirty tree. The main-checkout and `ralph/local` refusals are implemented but were not exercised (a test would have meant placing files in the protected checkout). A `.gitattributes` (`*.sh text eol=lf`) was added on that branch because `core.autocrlf=true` checks `loop_auto.sh` out with CRLF, which breaks bash.

### Guard-rails (specification)
| Control | Setting |
|---|---|
| Isolation | One dedicated worktree + branch per loop: `git worktree add ../hexa-worktrees/ralph-<task> -b ralph/<task> origin/main`. Never the main checkout or another agent's worktree. |
| No pushes to `main` | Remove `git pull … origin main` / `push … HEAD:main`; push only `ralph/<task>` and only after human OK; changes land via PR. |
| Permissions | Drop `--dangerously-skip-permissions`; use an allowlist (read/edit within the worktree, `flutter`, `pytest`, `git add/commit` only). Deny `git push`, `git reset --hard`, `git clean`, `rm -rf`, network deploy CLIs, DB migration commands. |
| Targets | `APP_URL`/`API_URL` = local or staging, never production. Test users/data seeded for QA only. |
| Budget | Small `--max-turns`, `MAX` rounds ≤ 5 for first run, `ROUND_TIMEOUT` ≤ 30m, kill switch `ralph/STOP`. |
| Scope | One task from `fix_plan.md` per loop; file globs declared up front so no two loops overlap. |
| Review | Human reads `ralph/progress.md` and the diff after each run; pushes manually. |
| Cost | Each round is a Claude run (plan usage); QA specs that call LLM providers cost provider tokens — exclude them. |

### Local test environment and first-run timing
The runner prepends the backend test venv (`hexa-worktrees/.venv-recovery`, Python 3.12) to `PATH`; backend pytest runs in the Ralph worktree (verified). **Do not start the first round yet:** `ralph/fix_plan.md` on `main` is dated 2026-11-08 and its first open task (B1e, `test_staff_cannot_edit_payment_but_can_receive_delivery_without_financials`) fails on `main` but is already fixed by PR #8. Merge PR #8, rebase `ralph/controlled` onto the new `main`, refresh `fix_plan.md`, then run one round (`MAX=1`).

### Start conditions
All of: GitHub authenticated; correct Vercel/Render accounts connected; staging/local target defined; other sessions closed; guard-railed script reviewed by the owner.

## 4. Open actions

Owner: `gh auth login`; revoke exposed GitHub token; rotate TestSprite key and restart; complete Cloudflare API MCP sign-in; reconnect Vercel and Render to the Harisree account.
Then: TestSprite tool inspection and credit estimate; Cloudflare zone/DNS/Tunnel read-only inspection; confirm Vercel project `purchase-assiastant` and Render `my-purchases-api` / `harisree_db`; implement the controlled Ralph script.
