# Supabase — this repo (XR project)

Committed reference only. **Do not put passwords, PATs, or anon keys in git.**

## Database connection (FastAPI / Alembic)

| Field | Value |
|-------|--------|
| Host | `db.xrkwlixlntujkhsaepbh.supabase.co` |
| Port | `5432` |
| Database | `postgres` |
| User | `postgres` |

Supabase may warn that the **direct connection is not IPv4 compatible**. From IPv4-only networks (many cloud hosts), use the **Session** or **Transaction pooler** string from **Supabase Dashboard → Connect** instead of `db.*:5432`.

Paste secrets only into **`backend/.env`** (gitignored). See repo root **[`.env.example`](../.env.example)**:

- Prefer **`postgresql+asyncpg://...`** for the API (`DATABASE_URL`), or **`DATABASE_POOLER_URL` + `DATABASE_POOLER_PASSWORD`** when using the Supabase pooler (see [`backend/app/database.py`](../backend/app/database.py)).

Sync URL shape (never commit the real URL):

```text
postgresql://postgres:[YOUR-PASSWORD]@db.xrkwlixlntujkhsaepbh.supabase.co:5432/postgres
```

## Cursor — Supabase MCP (optional)

Official server: `@supabase/mcp-server-supabase`. It talks to Supabase APIs using a **personal access token** (not the DB password):

1. Create a token: [Supabase account → Access tokens](https://supabase.com/dashboard/account/tokens).
2. Copy [`config/supabase.mcp.template.json`](../config/supabase.mcp.template.json) to **`.cursor/mcp.json`** in this repo (**`.cursor/mcp.json` is gitignored**).
3. Replace `REPLACE_WITH_PERSONAL_ACCESS_TOKEN_FROM_SUPABASE_DASHBOARD` with your token.
4. Restart Cursor → **Settings → Features → MCP** and enable the server.

If your team shares the repo, each developer keeps their own `.cursor/mcp.json` locally; only the template is tracked.

### Supabase Agent Skills (optional)

From the repo root:

```bash
npx skills add supabase/agent-skills
```

(Follow any prompts; skills live in your Cursor skills directory.)

## If a secret was pasted in chat

Rotate the **database password** and any **tokens** exposed, then update `backend/.env` and MCP config only on your machine.
