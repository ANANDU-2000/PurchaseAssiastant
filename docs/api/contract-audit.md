# API / Flutter contract audit (living doc)

Generated during HEXA Page Flow Completion. Compares **Flutter** (`flutter_app/lib/core/api/hexa_api.dart`), **FastAPI** (`backend/app/routers/`), and **OpenAPI** (`docs/api/openapi.yaml`).

## Aligned (implemented on both sides)


| Area              | Notes                                                                                                                                    |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Auth              | `POST /v1/auth/register`, `POST /v1/auth/login` (email + password), `POST /v1/auth/google`, `POST /v1/auth/refresh`; Flutter stores JWTs in secure storage. |
| Me                | `GET /v1/me/businesses`                                                                                                                  |
| Analytics summary | `GET /v1/businesses/{id}/analytics/summary?from=&to=`                                                                                    |
| Entries list      | `GET /v1/businesses/{id}/entries` with `from`, `to`, `item`                                                                              |
| Entries create    | `POST /v1/businesses/{id}/entries` with `confirm: false` (preview JSON) or `confirm: true` (201 + entry)                                 |
| Duplicate check   | `POST /v1/businesses/{id}/entries/check-duplicate`                                                                                       |
| Suppliers         | `GET` / `POST /v1/businesses/{id}/suppliers`                                                                                             |
| Brokers           | `GET /v1/businesses/{id}/brokers` (read-only)                                                                                            |


## Backend implemented; Flutter wired in this pass


| Endpoint                                     | Purpose                                                                                                         |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `GET /v1/businesses/{id}/entries/{entry_id}` | Entry detail for drill-down — implemented in `backend/app/routers/entries.py`; Flutter route `/entry/:entryId`. |


## OpenAPI / docs drift (track in `test-and-doc-sync`)


| Item                             | Status                                                                                                                                         |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET/PATCH /entries/{entryId}`   | **GET** implemented; **PATCH** still not implemented in FastAPI (defer). OpenAPI still lists PATCH — mark as optional or remove until shipped. |
| `POST /entries/parse`            | Stub in backend; full AI parse is Phase 3.                                                                                                     |
| Media / WhatsApp / Admin metrics | Stubs or partial; not required for MVP app flows.                                                                                              |


## Environment keys vs feature phase


| Keys                                                              | When required                                                     |
| ----------------------------------------------------------------- | ----------------------------------------------------------------- |
| `DATABASE_URL`, `JWT_`*, optional `GOOGLE_OAUTH_CLIENT_IDS`       | MVP local + email/password + optional Google Sign-In              |
| `OPENAI_*`, `OCR_*`, `STT_*`, `DIALOG360_*`, `S3_*`, `RAZORPAY_*` | Only when building parse, scan, voice, WhatsApp, billing features |


See root [.env.example](../../.env.example).