# fix_plan_android — Android app + install + cloud (Ralph picks these after fix_plan.md P0–P2)

- [ ] Add Android platform: in flutter_app run `flutter create --platforms=android --org com.hexastack --project-name purchase_assistant .` (keeps existing lib/). Set applicationId `com.hexastack.harisree`, app name "Harisree Purchase", launcher icon from existing assets, minSdk 23. Commit android/ (no keystore).
- [ ] Permissions audit in AndroidManifest: INTERNET, CAMERA (barcode scan), POST_NOTIFICATIONS, USE_BIOMETRIC. Nothing else. Set `usesCleartextTraffic=false`.
- [ ] Make plugins work on Android: mobile_scanner, local_auth (needs FragmentActivity), flutter_local_notifications (channel + icon), image_picker, permission_handler, printing/pdf, share_plus, flutter_secure_storage. Fix any runtime error found in an emulator/APK smoke run.
- [ ] Release signing: create upload keystore LOCALLY (human step, never committed); `android/key.properties` gitignored; Gradle reads it; CI reads keystore from GitHub secrets (base64) only.
- [ ] GitHub Actions `android-release.yml`: on tag `v*` → flutter build apk --release --split-per-abi + appbundle, `--dart-define=API_BASE_URL=https://my-purchases-api.onrender.com`, upload to GitHub Release. APK name `harisree-purchase-vX.Y.Z.apk`.
- [ ] In-app update check: on start call `GET /v1/app/version` (backend returns latest versionCode + apk url); if newer, show a clear "Update available" button. Backend config via env.
- [ ] Share/install page: static `/install` route on Vercel with big "Download Android app" button (GitHub Release link), "Install on iPhone/any phone: Add to Home Screen" steps (PWA), QR code. Large text, plain language.
- [ ] Real-device QA checklist file `ralph/ANDROID_QA.md` (install, login, scan barcode, count stock, offline banner, notification, rotate, back button) — loop runs emulator smoke if available, else marks [!] for human run.
- [ ] Play Store later (optional): internal testing track via Play Console — human step.

## Cloud (Render + DB + Vercel)
- [ ] Render: blueprint `render.yaml` in repo for backend + Postgres (no secrets in file; `sync: false` vars). Health check `/health/ready`, autoDeploy on main, region same as DB (Singapore).
- [ ] Render env: AUTO_MIGRATE=1, DATABASE_POOL_SIZE sized to plan, CORS_ORIGINS exact list. (Human sets secrets in dashboard.)
- [ ] Rotate-secrets runbook in DEPLOYMENT.md (DB password, JWT x2, OpenAI, GitHub token) — steps only, no values.
- [ ] Backups: db-backup.yml uses `DATABASE_URL` GitHub secret, weekly + restore test documented.
- [ ] Vercel: `API_BASE_URL` env set; preview deploys use staging API or are disabled; security headers (CSP, X-Content-Type-Options, Referrer-Policy) in vercel.json.
- [ ] Uptime: free UptimeRobot/GitHub Action ping on `/health/ready` with failure notice to email/WhatsApp.
