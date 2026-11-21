# Recovery Status

Last updated 2026-11-21. "Verified" = exercised in a real session. Nothing here has been pushed.

## 1. Integration verification

| Integration | State | Evidence / next action |
|---|---|---|
| Graphify CLI + MCP | Verified | JSON-RPC handshake lists 12 tools; graph readable (19,658 nodes). Requires `graphifyy[sql,mcp]`. |
| Browser (Claude in Chrome) | Verified | Tab group created. |
| Namecheap | Verified, correct account | `harisreeagency.online` registered to 2027-08-07; registrant is the owner; nameservers `rene.ns.cloudflare.com`, `coraline.ns.cloudflare.com`. DNS cannot be edited at Namecheap (zone is on Cloudflare). |
| GitHub CLI | **Verified** | Browser device-flow login as `ANANDU-2000` (keyring, HTTPS; scopes `repo`, `read:org`, `gist`). Repo permission: ADMIN. PR #8 latest CI run: success. PR #9 CI: failing in "Alembic migrations (SQLite smoke)" (`sqlite3.ProgrammingError: You can only execute one statement at a time`) — same failure PR #8 fixed; PR #9 likely needs the #8 fixes (rebase after #8 merges, with approval). Previously exposed PAT must still be revoked by the owner. |
| TestSprite MCP | **Blocked** | Env var `TESTSPRITE_API_KEY` is set at user scope but absent from the running session's process; tools not inspected; 0 credits used. Owner rotates key, sets new value, restarts Claude Code. |
| Cloudflare Workers MCP (claude.ai) | Partial | Workers/KV/D1/R2/Hyperdrive only; 0 workers. Cannot see zones, DNS, tunnels. |
| Cloudflare API MCP | **Added, needs sign-in** | Registered at user scope (`cloudflare-api` → `https://mcp.cloudflare.com/mcp`); status "Needs authentication". OAuth must be completed by the owner in an interactive session (`/mcp`). Zone/DNS/Tunnel checks are pending on this. |
| Vercel (claude.ai connector) | **Wrong account** | Signed in as the SBSOL account; projects `proimprint-videomaker`, `proimprint-ai`, `sbsol-ai-tracker`; no `purchase-assiastant`. Reconnect with the Harisree-owning account. |
| Render (claude.ai connector) | **Wrong account** | Workspace "ANANDU SBSOL TESTING"; ProImprint services; suspended `proai_catalog` DB; no `my-purchases-api` / `harisree_db`. Reconnect with the Harisree-owning account. Project-local `render-harisree` MCP (`RENDER_API_KEY`) is unverified; a direct API call with that key was blocked by the permission classifier and not retried. |
| PRO_AGENT connector | Ignored | Unrelated; HTTP 503. |
| Ralph Loop | Installed, idle, **not safe to start as-is** | See §3. |

## 2. Code state (nothing pushed)

| Branch / worktree | Commits |
|---|---|
| `fix/ci-recovery` (`hexa-worktrees/fix-ci-recovery`) | `3cdabea` stale-stock no-auto-force fix + stale scan-card test fix. Another session was concurrently editing Flutter tests in this worktree; its uncommitted changes were left untouched. |
| `docs/ai-environment` (`hexa-worktrees/ai-docs`) | `646941b`, `d74d868`, `f7c29b0`, plus this file |
| `ralph/local` (main checkout) | Untouched; 726 dirty files preserved |

Tests: backend pytest 327 passed; `flutter analyze` clean; full Flutter suite had ~6 failures in files being rewritten by the other session — re-run once that session is stopped.

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

### Required guard-rails (to implement in a copy, e.g. `ralph/loop_controlled.sh`; do not edit the original)
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

### Start conditions
All of: GitHub authenticated; correct Vercel/Render accounts connected; staging/local target defined; other sessions closed; guard-railed script reviewed by the owner.

## 4. Open actions

Owner: `gh auth login`; revoke exposed GitHub token; rotate TestSprite key and restart; complete Cloudflare API MCP sign-in; reconnect Vercel and Render to the Harisree account.
Then: TestSprite tool inspection and credit estimate; Cloudflare zone/DNS/Tunnel read-only inspection; confirm Vercel project `purchase-assiastant` and Render `my-purchases-api` / `harisree_db`; implement the controlled Ralph script.
