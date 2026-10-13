# PPAC · KYC Onboarding

**English** · [Tiếng Việt](README.vi.md)

Senior Full-stack take-home assignment: a mobile KYC (Know Your Customer) onboarding flow with a real backend.

| Project | What it is | Docs |
|---|---|---|
| [`kyc_service/`](kyc_service) | REST API - TypeScript, Express 5, Prisma, Zod. Runs on **Cloudflare Workers + D1 + R2** (Durable Object for the simulated review) or locally as a Node server with SQLite | [README](kyc_service/README.md) · [Tiếng Việt](kyc_service/README.vi.md) |
| [`kyc_app/`](kyc_app) | Flutter app (Android / iOS) - BLoC + rxdart, Dio, custom camera overlays, encrypted draft, resume after restart | [README](kyc_app/README.md) · [Tiếng Việt](kyc_app/README.vi.md) |

**System diagram:** [`kyc_service/docs/system-architecture.html`](kyc_service/docs/system-architecture.html) - download and open it in a
browser (architecture, KYC state machine, sequence diagrams, system-to-system interactions).

**Live API:** `https://kyc-service.tranduchau10d4.workers.dev` (health check: `/health`).

## Features

- Sign up / log in / log out, JWT access + rotating refresh tokens with reuse detection
- 5-step wizard: personal details (validated on both sides) → ID document photo → selfie → review & edit → submit
- Custom camera overlays (ID rectangle, face oval), compression, EXIF removal
- Draft saved on the device (AES-256-GCM) and on the server: kill the app at any step and resume where you left off
- Verification status with polling; simulated reviewer decides after ~10 s:
  **approved** → profile screen, **rejected** (final), **resubmission requested** → fix the flagged items and resubmit
- Private photo storage behind short-lived signed URLs; screenshot / app-switcher protection on the device
- Tests: 58 unit / HTTP + 4 end-to-end on the backend, BLoC / mapper / storage / widget tests on the app

## Quick start

```bash
# Backend (local Node server, no cloud account needed)
cd kyc_service
cp .env.example .env
npm install && npm run setup && npm run dev      # http://localhost:3000

# App
cd ../kyc_app
cp .env.example .env                             # API_BASE_URL: local server or the live Worker URL
flutter pub get
flutter run --dart-define-from-file=.env         # or the Run button in Android Studio / VS Code
```

Deploying the backend to Cloudflare: see [kyc_service README → Deploying to Cloudflare](kyc_service/README.md#deploying-to-cloudflare-workers--d1--r2).

## Demo scenarios

Use a new account for each scenario; the outcome depends on the full name entered in step 1.

| Full name | Result about 10 s after submitting |
|---|---|
| `Nguyen Van A` | Approved → *My profile* |
| `Reject Tester` | Rejected (final) |
| `Retake Tester` | Selfie retake requested → retake, resubmit → approved |

## Architecture at a glance

- **Backend:** TypeScript, Express 5, Prisma, Zod, layered (routes → controllers → services → repositories).
  One codebase, two runtimes: Node + SQLite locally, **Cloudflare Workers + D1 + R2** in production.
- **App:** Flutter, BLoC + rxdart, Dio with auth-refresh and retry interceptors, encrypted local draft.
- **KYC state machine:** `DRAFT → SUBMITTED → PROCESSING → APPROVED | REJECTED | RESUBMISSION_REQUESTED`,
  every transition is a conditional `UPDATE` with a status-history row.
- Details: [backend architecture](kyc_service/README.md#architecture) · [app architecture](kyc_app/README.md#architecture) · [diagram](kyc_service/docs/system-architecture.html).

## Security considerations

- Short-lived access JWT + rotating refresh tokens with reuse detection; only token hashes are stored.
- Photos are private: magic-byte validation, size limits, EXIF removal, short-lived HMAC-signed URLs.
- On the device: tokens in the secure keystore, draft encrypted with AES-256-GCM, screenshot / app-switcher protection.
- PII is kept out of logs; passwords hashed with bcrypt; input validated with Zod on the server and in the app.
- Details: [backend PII & security](kyc_service/README.md#pii--security) · [app security](kyc_app/README.md#security--pii).

## Key trade-offs

- **D1 has no interactive transactions** - guarded conditional writes keep races safe; all-or-nothing atomicity across two statements is lost on Cloudflare.
- **Review is simulated** (database-driven worker / Durable Object alarm) instead of a real KYC vendor.
- **Rate limiting is per isolate** on Workers; a global limit needs Cloudflare WAF rules.
- **Assumptions** are listed in [backend](kyc_service/README.md#assumptions) and [app](kyc_app/README.md#assumptions).

## With more time

- Field-level (envelope) encryption of PII columns and server-side image re-encoding + malware scan.
- A real KYC vendor (document authenticity, liveness, face match) with webhooks instead of polling.
- Queue-based review, PostgreSQL, OpenAPI spec, audit log of document access, data-retention job, access-token deny list.
- App: certificate pinning, offline upload queue, integration tests on real devices, localization.

## Repository layout

```
.
├── kyc_service/   # backend (src/, worker/, prisma/, migrations/, test/, docs/)
└── kyc_app/       # Flutter app (lib/, test/, android/, ios/)
```

Secrets are never committed: `.env`, `.dev.vars` and local databases / photos are git-ignored; production
secrets live in Cloudflare (`wrangler secret put`).
