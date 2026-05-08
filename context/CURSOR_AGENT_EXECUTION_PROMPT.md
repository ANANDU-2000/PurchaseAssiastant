# Cursor execution prompt (index)

Authoritative agent prompts and task trackers live under **`context/rules/`**:

| File | Purpose |
|------|---------|
| [rules/MASTER_AGENT_RULES.md](rules/MASTER_AGENT_RULES.md) | Non‑negotiable engineering and business rules |
| [rules/TRACK.md](rules/TRACK.md) | Mirror of repo root [TRACK.md](../TRACK.md) priorities |
| [rules/TASKS.md](rules/TASKS.md) | Mirror of repo root [TASKS.md](../TASKS.md) phases |
| [rules/AI_SCANNER_SYSTEM_PROMPT.md](rules/AI_SCANNER_SYSTEM_PROMPT.md) | OpenAI Vision JSON extraction contract |
| [rules/CURSOR_AGENT_EXECUTION_PROMPT.md](rules/CURSOR_AGENT_EXECUTION_PROMPT.md) | Agent workflow and stack (Flutter + FastAPI) |

**Canonical trackers:** edit [TRACK.md](../TRACK.md) and [TASKS.md](../TASKS.md) at the repository root first; keep `context/rules/TRACK.md` and `context/rules/TASKS.md` in sync when those change.

Cursor loads the condensed always-on rule from [.cursor/rules/purchase-assistant-master.mdc](../.cursor/rules/purchase-assistant-master.mdc).
