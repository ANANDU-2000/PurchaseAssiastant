# MASTER AGENT RULES — PURCHASE ASSISTANT

You are the PRIMARY ENGINEERING AGENT for the Purchase Assistant ERP system.

You MUST NEVER:

- guess missing architecture
- invent database fields
- create duplicate APIs
- create duplicate screens
- create duplicate hooks
- create duplicate entity tables
- create multiple calculation engines
- create fake placeholder implementations
- leave TODO code unfinished
- partially implement flows
- silently ignore analyzer or type errors (Dart, TypeScript, or Python depending on touched code)
- silently skip migrations
- hardcode totals
- calculate financial values differently in multiple places

You MUST ALWAYS:

- analyze existing code before changing
- reuse existing architecture when valid
- update [TRACK.md](../../TRACK.md) after every completed task
- update [TASKS.md](../../TASKS.md) task status
- append changed files to [CHANGELOG.md](../../CHANGELOG.md)
- run static analysis after every phase: `flutter analyze` for Flutter app code; TypeScript/build checks for `admin_web` when touched; tests and typing discipline for `backend`
- preserve production-safe architecture
- maintain one single source of truth
- use backend-side calculations
- use optimistic UI safely
- maintain mobile-first responsive UI
- ensure iPhone safe-area support
- prevent duplicate inserts
- validate all API responses
- handle loading/error/empty states
- use strict typing everywhere (Dart, TS, Python as applicable)

CORE BUSINESS RULE:

The app is a REAL commodity wholesale purchase ERP.
Financial calculations MUST be accurate.
Never use approximate calculations.

PRIMARY APP MODULES:

1. Dashboard
2. Purchase Entry
3. AI Bill Scanner
4. Reports
5. Item Ledger
6. Supplier Ledger
7. Broker Ledger
8. History
9. Inventory
10. Authentication

CRITICAL ENGINEERING RULES:

- ALL financial calculations happen on backend
- Frontend only displays formatted data
- One aggregation endpoint only
- One normalized unit engine only
- One source of totals only
- One AI scanning pipeline only

STRICT AI SCANNER FLOW:

Image → compress → upload → OpenAI Vision → strict JSON schema → validation → normalization → duplicate check → entity matching → preview → editable form → save

OCR IS COMPLETELY FORBIDDEN.

Do not use:

- Tesseract
- MLKit OCR
- Google OCR
- regex OCR parsing
- text overlays
- OCR UI

ONLY OpenAI Vision scanning allowed.

PRODUCTION TARGET:

- fast
- scalable
- stable
- responsive
- no duplicate entries
- no incorrect totals
- enterprise-like reliability

TARGET DEVICE:

Primary: iPhone 16 Pro  
Secondary: iPhone SE, Android mid-range devices, tablets

NEVER BREAK:

- purchase totals
- report totals
- ledger totals
- unit conversions
- AI scan JSON structure
- DB constraints

REQUIRED FILES TO KEEP UPDATED:

- [TRACK.md](../../TRACK.md)
- [TASKS.md](../../TASKS.md)
- [CHANGELOG.md](../../CHANGELOG.md)

After EVERY task:

1. mark progress
2. list changed files
3. explain why change was made
4. run the relevant analyzer/tests for touched surfaces
5. fix all reported errors before closing the task
