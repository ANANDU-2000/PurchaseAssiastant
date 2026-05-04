# Supabase — this repo (XR project)

Committed reference only. **Do not put passwords, PATs, or anon keys in git.**

## Database connection (FastAPI / Alembic)


| Field    | Value                                 |
| -------- | ------------------------------------- |
| Host     | `db.xrkwlixlntujkhsaepbh.supabase.co` |
| Port     | `5432`                                |
| Database | `postgres`                            |
| User     | `postgres`                            |


Supabase may warn that the **direct connection is not IPv4 compatible**. From IPv4-only networks (many cloud hosts), use the **Session** or **Transaction pooler** string from **Supabase Dashboard → Connect** instead of `db.*:5432`.

Paste secrets only into `**backend/.env`** (gitignored). See repo root `**[.env.example](../.env.example)**`:

- Prefer `**postgresql+asyncpg://...**` for the API (`DATABASE_URL`), or `**DATABASE_POOLER_URL` + `DATABASE_POOLER_PASSWORD**` when using the Supabase pooler (see `[backend/app/database.py](../backend/app/database.py)`).

Sync URL shape (never commit the real URL):

```text
postgresql://postgres:[YOUR-PASSWORD]@db.xrkwlixlntujkhsaepbh.supabase.co:5432/postgres
```

## Cursor — Supabase MCP (optional)

Official server: `@supabase/mcp-server-supabase`. It calls Supabase **management / project APIs** using:


| Variable                    | What to paste                                                                                                                                                       |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**SUPABASE_ACCESS_TOKEN`** | A **[personal access token](https://supabase.com/dashboard/account/tokens)** from **Account Settings → Access Tokens** (your Supabase login), not project API keys. |


**Do not use**

- `**anon`** / `**service_role**` keys under **Project Settings → API** (those are for the Data/Auth REST client, not this MCP server).
- The **database password**.
- Putting real secrets in `**config/supabase.mcp.template.json`** — it is tracked by git.

If the dashboard shows prefixed keys (e.g. `sb_publishable_*`, `sb_secret_*`), verify in Supabase docs that the value you copied is documented as `**SUPABASE_ACCESS_TOKEN**` / account access token for MCP—not a Postgres or client key.

### Local setup

1. Create a token: [Supabase → Access tokens](https://supabase.com/dashboard/account/tokens).
2. Copy the template → `**.cursor/mcp.json**` (gitignored), e.g. PowerShell:
  ```powershell
   Copy-Item "config\supabase.mcp.template.json" ".cursor\mcp.json" -Force
  ```
3. Replace `**REPLACE_WITH_PERSONAL_ACCESS_TOKEN_FROM_SUPABASE_DASHBOARD**` in `**.cursor/mcp.json**` only.
4. Restart Cursor → **Settings → Features → MCP** — enable `**supabase`**.

Keep `**--project-ref=xrkwlixlntujkhsaepbh**` in `args` to scope MCP to this project.

If your team shares the repo, only `**.cursor/mcp.json**` (local) holds the token.

---

## Cursor — Render MCP (optional)

Official docs: **[Render MCP Server](https://render.com/docs/mcp-server)**.

Create an **[API key](https://dashboard.render.com/u/settings#api-keys)** (Account Settings). Keys often look like `rnd_...`.

**Never** commit keys. Use `**config/render.mcp.template.json`** (placeholder only), or merge this block into `**mcpServers**` in `**.cursor/mcp.json**`:

```json
"render": {
  "url": "https://mcp.render.com/mcp",
  "headers": {
    "Authorization": "Bearer REPLACE_WITH_RENDER_ACCOUNT_API_KEY"
  }
}
```

Then **Settings → Features → MCP** → enable `**render`** (and `**supabase**` if configured). Restart Cursor if the server stays grey.

Alternative (stdin transport): docs also show `**npx mcp-remote https://mcp.render.com/mcp**` with `**RENDER_API_KEY**` in `env`; use that if Cursor does not accept the `url` form on your OS.

### Combined `mcp.json`

Keep `**supabase**` and `**render**` as two keys under `**mcpServers**` in the same `.cursor/mcp.json` file (still gitignored). Do not overwrite one with the other.

### Supabase Agent Skills (optional)

From the repo root:

```bash
npx skills add supabase/agent-skills
```

(Follow any prompts; skills live in your Cursor skills directory.)

## If a secret was pasted in chat

Rotate the **database password** and any **tokens** exposed, then update `backend/.env` and MCP config only on your machine.