# API Audit — Phase 8: Users / Activity

**Date:** 2026-07-28  
**Router:** `backend/app/routers/users.py` (+ auth refresh JWT)

## Prod evidence

- No `/users*` or `/activity*` **5xx** in sampled request logs
- Mutations already `commit()` on create/patch/delete/bulk/permissions

## Findings

| ID | Severity | Issue | Status |
|----|----------|-------|--------|
| USERS-C1 | Critical | Password reset did not bump `token_version`; refresh JWT had no `tv` → old sessions survived reset | **Fixed** |
| USERS-H1 | High | Deactivate did not revoke tokens (access/refresh) | **Fixed** |
| USERS-H2 | High | `PATCH …/permissions` skipped `_guard_actor_target` (admin could edit owner) | **Fixed** |
| USERS-H3 | High | Staff could `GET activity-log?user_id=` for another user | **Fixed** |
| USERS-M1 | Medium | `list_users` N+1 `_user_row` stats | **Fixed** (batched) |

## JWT change

Refresh tokens now embed `tv` (token_version), same as access. `POST /v1/auth/refresh` rejects mismatched `tv` (`Token revoked`).

## Tests

- `tests/test_users_management.py` — reset revoke, admin→owner permissions 403, staff activity IDOR 403
- `tests/test_auth_login_email.py` — refresh after block/deactivate updated

## Open Critical

**None** for Users after this pass.

## Next

Warehouse/Ops → Exports → Utilities → Public.
