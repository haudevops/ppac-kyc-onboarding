# PPAC · KYC Onboarding

**English** · [Tiếng Việt](README.vi.md)

Senior Full-stack take-home assignment: a mobile KYC (Know Your Customer) onboarding flow with a real backend.

| Project | What it is | Docs |
|---|---|---|
| [`kyc_service/`](kyc_service) | REST API - TypeScript, Express 5, Prisma, Zod. Runs on **Cloudflare Workers + D1 + R2** (Durable Object for the simulated review) or locally as a Node server with SQLite | [README](kyc_service/README.en.md) · [Tiếng Việt](kyc_service/README.vi.md) |
| [`kyc_app/`](kyc_app) | Flutter app (Android / iOS) - BLoC + rxdart, Dio, custom camera overlays, encrypted draft, resume after restart | [README](kyc_app/README.en.md) · [Tiếng Việt](kyc_app/README.vi.md) |

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

Deploying the backend to Cloudflare: see [kyc_service README → Deploying to Cloudflare](kyc_service/README.en.md#deploying-to-cloudflare-workers--d1--r2).

## Demo scenarios

Use a new account for each scenario; the outcome depends on the full name entered in step 1.

| Full name | Result about 10 s after submitting |
|---|---|
| `Nguyen Van A` | Approved → *My profile* |
| `Reject Tester` | Rejected (final) |
| `Retake Tester` | Selfie retake requested → retake, resubmit → approved |

## Repository layout

```
.
├── kyc_service/   # backend (src/, worker/, prisma/, migrations/, test/, docs/)
└── kyc_app/       # Flutter app (lib/, test/, android/, ios/)
```

Secrets are never committed: `.env`, `.dev.vars` and local databases / photos are git-ignored; production
secrets live in Cloudflare (`wrangler secret put`).
