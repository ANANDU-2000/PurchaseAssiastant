# SPEC 13 — REPO HYGIENE (GITIGNORE / BUILD ARTIFACTS)
> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS
| Task | Status |
|------|--------|
| Ignore Python caches (`__pycache__`, `.pytest_cache`, `*.pyc`) | ⚠️ Partial |
| Ignore Flutter build outputs (`.dart_tool`, `build/`) | ⚠️ Partial |
| Ignore release artifacts (`release_pack/`, `*.zip`) | ✅ Done |
| Keep `context/` tracked (specs + trackers) | ✅ Done |
| Ensure `git status` is clean of generated files | ✅ Done |

---

## FILES TO EDIT
```
.gitignore
```

---

## WHAT TO DO

### ❌ TASK 13-A: Update `.gitignore` to exclude generated files

Add ignores for:
- `backend/.pytest_cache/`
- `backend/**/__pycache__/`
- `flutter_app/.dart_tool/`
- `flutter_app/build/`
- `flutter_app/.flutter-plugins-dependencies`
- `release_pack/`
- `*.zip`
- `*.jpeg` / `*.jpg` in `data/` (unless intentionally versioned)

---

## VALIDATION
- [ ] `git status --porcelain` shows **no** build caches (`.dart_tool`, `build`, `__pycache__`, `.pytest_cache`)
- [ ] Only intentional source/config files remain untracked

