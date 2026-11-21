# Domain, Cloudflare, Vercel and API cut-over runbook

Target: frontend `https://harisreeagency.online` (+ `www`) and `https://purchase-assiastant.vercel.app` on Vercel;
API `https://api.harisreeagency.online` through a Cloudflare Tunnel to FastAPI on the Windows Server.
**Nothing here has been executed.** Status of each step is at the end. Steps marked OWNER need your login.

## 0. Current facts (checked 2026-11-21)
- Domain NS = `verify-contact-details.namecheap.com`, `failed-whois-verification.namecheap.com`; `@`, `www` and `api` resolve to Namecheap's holding address. This is the registrar's "contact details not verified" hold: **no DNS record can work until it is lifted.**
- Frontend `purchase-assiastant.vercel.app` serves (HTTP 200). API on Render answers 503 `Service Suspended` (`suspend-by-user`).
- The Flutter app reads the compile-time define `API_BASE_URL`; `scripts/vercel-flutter-build.sh` passes the Vercel project variable of the same name through `--dart-define`.

## 1. OWNER - lift the Namecheap hold
1. Namecheap > Domain List > `harisreeagency.online` > Manage. Look for the red "verify contact details / WHOIS" banner.
2. Open the verification email Namecheap sent to the **registrant email** and click the link. If you cannot find it or the address is wrong: update the registrant email in Contact info, then use "Resend verification".
3. Wait for the status to clear (usually minutes to a few hours). Check from any PC: `nslookup -type=NS harisreeagency.online 8.8.8.8` must no longer show `verify-contact-details` or `failed-whois-verification`.
4. **Before changing anything else, export the existing DNS records** (Advanced DNS) - especially MX, SPF/DKIM/DMARC TXT records - so email is preserved.

## 2. OWNER - Cloudflare zone (needs the Cloudflare account login)
1. Add site `harisreeagency.online` (Free plan). Cloudflare imports existing records; **compare with the export from step 1.4 and add anything missing, keeping all MX/TXT records exactly.**
2. Cloudflare shows two nameservers. At Namecheap set the domain to Custom DNS with exactly those two (needs your approval; it is the only change that moves DNS authority). Wait until the zone shows Active.
3. Zero Trust > Networks > Tunnels > Create (Cloudflared): name `hexa-api`. Copy the token **only** into `C:\hexa\config\cloudflared.token` on the server. Public hostname: `api.harisreeagency.online` -> `http://localhost:8000`. Cloudflare creates the proxied CNAME for `api` itself.

## 3. DNS records after the zone is active
| Name | Type | Target | Proxy |
|---|---|---|---|
| `api` | CNAME | `<tunnel-id>.cfargotunnel.com` (created by the tunnel) | Proxied |
| `@` | CNAME (flattened) | `cname.vercel-dns.com` | **DNS only** |
| `www` | CNAME | `cname.vercel-dns.com` | **DNS only** |
| MX / TXT (SPF, DKIM, DMARC) | as exported | unchanged | - |
Vercel needs DNS-only records to issue its certificate; do not proxy `@`/`www`.

## 4. Server: tunnel and API (prepared in PR #9 `deploy/windows/`)
Run `install-server.ps1`, fill `backend.env` (CORS below), `deploy-release.ps1`, then `install-cloudflared.ps1`. PostgreSQL stays on localhost; no inbound firewall rule for 5432 or 8000.

Backend CORS (must include every browser origin of the frontend):
`CORS_ORIGINS=https://purchase-assiastant.vercel.app,https://harisreeagency.online,https://www.harisreeagency.online`

## 5. Verify the API BEFORE touching the frontend
```
curl -s -o /dev/null -w "%{http_code}\n" https://api.harisreeagency.online/health/live    # 200
curl -s https://api.harisreeagency.online/health/ready                                    # status ok, db ok, schema_ok true
curl -s -i -H "Origin: https://harisreeagency.online" https://api.harisreeagency.online/health/live | grep -i access-control-allow-origin
```
Then log in with a test company, create a supplier/item/purchase, check stock, confirm a second company cannot see it.

## 6. Vercel
1. Vercel > project (the one that serves `purchase-assiastant.vercel.app`; it lives in team `anandukrishnapa2000-gmailcoms-projects`) > Settings > Domains: add `harisreeagency.online` and `www.harisreeagency.online`. Keep `purchase-assiastant.vercel.app`. Do not remove existing domains.
2. Settings > Environment Variables: `API_BASE_URL` = `https://api.harisreeagency.online` for **Production** only (Preview/Development stay on the staging or local API). It is a public, compile-time value; never put secrets in it.
3. Merge the cut-over PR (it removes the build-script override that forces the Render URL and the CI rule that rejects the new host), then redeploy. **Do this only after step 5 passes.**
4. Smoke: open `https://harisreeagency.online`, login, browser console shows no CORS/network errors.

## 7. Rollback
Vercel: promote the previous deployment, or set `API_BASE_URL` back to the Render URL and redeploy. Render stays untouched and suspended-but-intact until a verified stabilisation period.

## Status
| Step | Status |
|---|---|
| 1 Namecheap hold | BLOCKED (owner) |
| 2 Cloudflare zone and tunnel | BLOCKED (owner login; no Cloudflare API tool connected) |
| 3 DNS records | NOT STARTED (depends on 1-2) |
| 4 Server and tunnel service | BLOCKED (no server access); scripts ready in PR #9 |
| 5 API verification | NOT STARTED |
| 6 Vercel domain/env and cut-over PR | PREPARED (this PR, draft, do not merge yet) |
