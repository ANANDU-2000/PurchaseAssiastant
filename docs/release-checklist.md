# Release checklist (HEXA)

Use before tagging a production release.

- [ ] `APP_ENV=production` startup passes `validate_production_safety()` (JWT, OTP).
- [ ] `.env` matches [`.env.example`](../.env.example) for all **enabled** features.
- [ ] `docs/api/openapi.yaml` matches live routes (spot-check `/health`, `/v1/auth/*`, `/v1/admin/*`).
- [ ] Backend: `pytest` green; Flutter: `flutter test` / `flutter analyze` clean.
- [ ] WhatsApp: webhook signature verified in staging; idempotency verified with Redis.
- [ ] No auto-save paths without user confirmation (OCR/voice/preview flows).
