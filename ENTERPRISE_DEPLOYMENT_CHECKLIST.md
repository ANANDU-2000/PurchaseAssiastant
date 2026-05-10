# Enterprise deployment checklist

- [ ] **Env:** Backend `DATABASE_URL`, JWT secrets, OpenAI keys, Supabase URL/keys set in hosting (e.g. Render).
- [ ] **Migrations:** `alembic upgrade head` (or Supabase migration apply) including optional `supabase_020_ocr_learning.sql` when RLS designed.
- [ ] **CORS:** Origins include Flutter web / admin hosts.
- [ ] **Health:** `/health` monitored.
- [ ] **Backups:** Postgres PITR or daily logical backup.
- [ ] **CI:** Green on `main` — `pytest`, `flutter analyze`, `flutter test`.
- [ ] **Smoke:** Run `QA_MASTER_CHECKLIST.md` P0 items post-deploy.
