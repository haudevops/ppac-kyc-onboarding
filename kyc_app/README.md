# KYC Onboarding App (Flutter)

**English** · [Tiếng Việt](README.vi.md)

Cross-platform (Android / iOS) identity-verification wizard for the KYC Onboarding take-home
assignment. It talks to the real backend in [`../kyc_service`](../kyc_service) (no mocks): sign in,
enter personal details, photograph the ID and a selfie with guided camera overlays, review and
submit, then follow the verification status until it is approved, rejected or sent back for
changes. A draft survives app kills and restarts at every step.

> **System diagram:** [`../kyc_service/docs/system-architecture.html`](../kyc_service/docs/system-architecture.html)
> (open in a browser) - how the app, the API, object storage and the database talk to each other.

**Stack:** Flutter 3.x (Dart ≥ 3.13) · `flutter_bloc` + `rxdart` · `dio` (JWT refresh, retry,
multipart) · `shared_preferences` (encrypted draft) + `flutter_secure_storage` (tokens, draft key) ·
`cryptography` (AES-256-GCM) · `camera` (custom overlays) + `image_picker` · `flutter_image_compress` ·
`bloc_test` + `mocktail`

| Assignment requirement | Where |
|---|---|
| Authentication: login, session handling, logout | `features/auth` - `AuthBloc`, tokens in Keychain / Keystore, single-flight refresh, logout dialog |
| Personal details with validation | Step 1 - `PersonalDetailsValidator` (same rules as the backend), debounced autosave |
| ID document capture | Step 2 - custom camera with an ID-card rectangle, front / back (no back for passports) |
| Selfie capture | Step 3 - front camera with a face oval |
| Review, edit, submit | Step 4 - every section editable, consent, one multipart submit |
| Verification status, rejection, resubmission | Step 5 - rxdart polling; rejected (final) vs resubmission requested (fix flagged items) |
| Resume after closing the app | Encrypted local draft + server draft, reconciled by `KycResumeResolver` |
| Sensitive data, error handling, tests | See [Security & PII](#security--pii), [Networking](#networking), [Tests](#tests) |

---

## Run it

Requirements: Flutter SDK (Dart ≥ 3.13), Android Studio and / or Xcode, and the backend running.

```bash
# 1. Backend (see ../kyc_service/README.md)
cd ../kyc_service && npm install && npm run setup && npm run dev

# 2. App
cd ../kyc_app
cp .env.example .env          # then set API_BASE_URL for your device (table below)
flutter pub get
flutter run --dart-define-from-file=.env
flutter test
```

**Android Studio / VS Code:** the run configurations in `.idea/runConfigurations/main_dart.xml` and
`.vscode/launch.json` already pass `--dart-define-from-file=.env`, so the normal **Run ▶** button works.

### Configuration (`.env`)

`.env` is git-ignored (template: `.env.example`) and **compiled into the app at build time**: after
editing it, stop the app and run it again - hot reload / hot restart is not enough. Never put
secrets in it.

| Key | Default | Purpose |
|---|---|---|
| `API_BASE_URL` | emulator default | Backend URL without `/api/v1` (see the table below) |
| `API_CONNECT_TIMEOUT_MS` / `API_RECEIVE_TIMEOUT_MS` / `API_SEND_TIMEOUT_MS` | 10000 / 20000 / 60000 | Dio timeouts (send is long for image uploads) |
| `API_MAX_RETRIES` | 3 | Retries for transient failures |
| `KYC_STATUS_POLL_INTERVAL_MS` | 2000 | Status polling interval after submitting |
| `PROTECT_SCREEN` | `true` | Block screenshots / recording and hide the app in the app switcher |

### Which `API_BASE_URL`?

| Target | `API_BASE_URL` |
|---|---|
| Android emulator | empty (→ `http://10.0.2.2:3000`) or `http://localhost:3000` + `adb reverse tcp:3000 tcp:3000` |
| Real Android phone over USB | `http://localhost:3000` + `adb reverse tcp:3000 tcp:3000` (repeat after reconnecting the cable) |
| iOS simulator | empty or `http://localhost:3000` |
| iPhone / any phone on the same Wi-Fi | `http://<Mac name>.local:3000` (`scutil --get LocalHostName`) or `http://<Mac IP>:3000` (`ipconfig getifaddr en0`) |

Keep `PUBLIC_BASE_URL` in `kyc_service/.env` **equal to** `API_BASE_URL`, otherwise uploaded images
cannot be displayed. Quick check: open `<API_BASE_URL>/health` in the phone's browser.

The iOS simulator has no camera: use the **Gallery** button on the capture screen.

### Demo scenarios

The backend's simulated reviewer decides about 10 s after submission, based on the full name:

| Full name | Result in the app |
|---|---|
| anything normal, e.g. `Nguyen Van A` | **Approved** → *My profile* screen |
| contains `reject`, e.g. `Reject Tester` | **Rejected** (final) - contact support, no further edits |
| contains `retake`, e.g. `Retake Tester` | **Resubmission requested** for the selfie → retake it and submit again → approved |

- Use **a new email for every scenario** (one application per account).
- Watch the spelling: re**ject** is final, re**take** asks for a new selfie.
- *Rejected*: the screen shows the reason and "This decision is final…", with no edit button; it
  stays like that after restarting the app or logging in again.
- *Retake*: the reviewer's message is shown → **Fix and resubmit** opens the selfie step with the old
  photo removed → take a new one → Review → Submit → approved about 10 s later.
- Other outcomes (e.g. a new ID front photo) can be forced from the backend - see
  *Manual testing with the app* in the backend README.

To record the demo video, set `PROTECT_SCREEN=false`, re-run the app, and set it back afterwards.

---

## Architecture

```
lib/
├── main.dart                     # bootstrap (config, screen protection, DI)
├── app/                          # composition root (dependencies.dart), MaterialApp + auth gate, theme
├── core/
│   ├── bloc/event_transformers   # rxdart: droppable / restartable / debounce
│   ├── config/                   # AppConfig (values from .env)
│   ├── constants/                # countries
│   ├── error/app_exception       # one error type; parses the backend error envelope
│   ├── network/                  # ApiClient + AuthInterceptor, RetryInterceptor, SafeLogInterceptor
│   ├── security/                 # DraftCipher (AES-GCM), ScreenSecurity (FLAG_SECURE), PrivacyOverlay
│   ├── storage/token_storage     # Keychain / Keystore-backed token storage
│   ├── media/image_processor     # JPEG compression + EXIF stripping
│   ├── utils/                    # auth validators, date helpers
│   └── presentation/             # shared widgets, UiMessage (one-shot snackbars)
└── features/
    ├── auth/  {domain, data, presentation}   # login / register / logout / session check
    ├── kyc/
    │   ├── domain/      entities, KycRepository (interface), validators, resume resolver
    │   ├── data/        remote (Dio) + local (encrypted SharedPreferences + files) data sources, mappers
    │   └── presentation/
    │       ├── bloc/    KycBloc (events / states)
    │       ├── pages/   KycFlowPage (wizard host)
    │       ├── steps/   1 details · 2 document · 3 selfie · 4 review · 5 verification
    │       ├── camera/  custom camera page, overlay painter (rect / oval), preview
    │       └── widgets/ step indicator, document slot, date field
    └── profile/         # verified user's profile (ProfileCubit + page, zoomable photos)
```

Dependencies point inward: **presentation → domain ← data**. Blocs only know the
`KycRepository` / `AuthRepository` interfaces, so they are unit-tested with mocks. Use cases were
deliberately not added as a separate layer - with one repository per feature they would only
forward calls. Dependencies are wired by hand in `app/dependencies.dart`.

### The KYC flow (`KycBloc`)

| Step | What happens |
|---|---|
| **Resume** (`KycStarted`) | Loads the local draft and `GET /kyc`, then reconciles them (`KycResumeResolver`): the server decides the status, local edits win field by field, local photos win over server copies, and the saved step is clamped to the first incomplete step. A pending application goes to the status screen and resumes polling. If the backend is unreachable, the app continues from the local draft (offline banner). |
| **1. Details** | Debounced autosave on every change (`debounceTime` + `switchMap`). On "Continue" the same rules as the backend (name, adult DOB, ID number per document type / nationality, expiry, E.164 phone, ...) run in `PersonalDetailsValidator`; backend field errors are shown on the matching field. |
| **2. Document / 3. Selfie** | Custom camera → preview → compress (≤1600 px short edge, EXIF stripped) → stored under app documents → **uploaded in the background** (`POST /kyc/documents/:type`). Upload state is shown per photo (saved on device / uploading / uploaded / retry). |
| **4. Review** | Every section can be edited; consent checkbox; submit. |
| **5. Submit + status** | One multipart `POST /kyc/submit` with the details and only the photos the server doesn't have yet (upload progress shown). Then `GET /kyc/status` is polled with rxdart (`startWith` + `exhaustMap` + `takeWhileInclusive`) until the reviewer decides; refreshed on app resume and pull-to-refresh. **Approved** → profile. **Rejected** → final, contact support. **Resubmission requested** → the reviewer's message and the items to redo are shown; "Fix and resubmit" opens the first requested step, drops the flagged photos so they must be retaken, and shows the feedback on every affected step. |

Every state change that matters is written to the local draft, so killing the app at any point
resumes at the same step with the same inputs and photos. Details + current step are also synced
to the backend (`PUT /kyc/draft`) for cross-device resume.

Once **approved**, the user lands on **My profile** (`features/profile`): the data exactly as
verified by the backend (`GET /kyc`), selfie avatar, ID photos (tap to zoom), verification dates and
reference. Photo URLs are short-lived presigned URLs, renewed on pull-to-refresh or when the app
returns to the foreground after a few minutes.

### Networking

- **AuthInterceptor**: attaches the access token; on 401 refreshes once (single-flight, so
  concurrent 401s share one refresh - important because the backend rotates refresh tokens and
  revokes the session on reuse) and replays the request. If the refresh token is rejected, tokens
  are cleared and `SessionEvents` tells the `AuthBloc` to show the login screen (the local draft
  is kept, so the user resumes after logging in again).
  Expiry is detected on the **next API call**, not by a timer: an idle screen stays as it is until
  the user does something that reaches the server. Every refresh issues a new refresh token, so an
  active user is never logged out (sliding session).
- **RetryInterceptor**: exponential backoff + jitter for connection errors, timeouts, 429/502/503/504.
  Only idempotent methods, plus requests that opt in (KYC submit: a duplicate is answered with
  `409 KYC_NOT_EDITABLE`, which the bloc treats as "already submitted"). Multipart bodies are
  rebuilt from a factory before each retry. The refresh call is never retried.
- **SafeLogInterceptor** (debug only): method, path, status and duration - never headers or bodies.
- **Errors**: every failure becomes an `AppException` (network, timeout, validation with field
  errors, unauthorized, conflict, server), shown as a friendly message; field errors land on the
  matching input.

---

## Assumptions

- **Rejection vs. resubmission request.** `REJECTED` is a final decision; `RESUBMISSION_REQUESTED`
  carries the items to redo (`PERSONAL_DETAILS`, `ID_FRONT`, `ID_BACK`, `SELFIE`). See the
  backend README for the full state machine.
- One KYC application per user; the device draft is per user and wiped on logout.
- Adults only (18+), unexpired ID; a passport has no back side.
- The backend's simulated reviewer stands in for a KYC vendor; names containing "reject" /
  "retake" trigger the two negative outcomes for demos.

## Security & PII

- Tokens in Keychain / Keystore (`flutter_secure_storage`); stale iOS Keychain tokens are cleared
  on the first launch after reinstall.
- The draft (name, DOB, ID number, address) is persisted in SharedPreferences **encrypted with
  AES-256-GCM** (`core/security/draft_cipher.dart`). The random key lives in the Keychain / Keystore
  (`first_unlock_this_device`: never migrated to backups or other devices); a tampered or
  unreadable draft is discarded.
- **Screen protection** (`PROTECT_SCREEN=true` by default): Android sets `FLAG_SECURE`
  (no screenshots / recordings, blank recent-apps preview, `MainActivity.kt`); on both platforms a
  privacy overlay hides the UI whenever the app leaves the foreground, so the app-switcher snapshot
  never shows PII.
- Android `allowBackup="false"`: app data (draft, photos) is not copied to Google Drive backups.
- Photos are compressed with EXIF removed (no GPS location), kept in the app sandbox, and
  temporary camera files are deleted. On logout and once the application is approved, the local
  draft and photos are deleted.
- Displayed server images use short-lived presigned URLs that are never persisted.
- Trade-off: the compressed photos themselves are files in the app sandbox (protected by the OS
  sandbox and iOS Data Protection) but not encrypted by the app, because they are displayed and
  uploaded directly from disk. Encrypting them too is listed under next steps.

## Tests

```bash
flutter test
```

| File | Covers |
|---|---|
| `test/features/kyc/kyc_bloc_test.dart` | Resume, offline start, clamping to the first incomplete step, validation, submit sending only missing photos, server `KYC_INCOMPLETE` mapping, polling until a decision, resubmission flow, final rejection |
| `kyc_resume_resolver_test.dart` | Merging local and server drafts |
| `personal_details_validator_test.dart` | Field rules (age, ID formats, expiry, phone) |
| `kyc_mappers_test.dart` | API / draft mapping, resubmission items |
| `kyc_local_data_source_test.dart` | Encrypted draft store: no plain-text PII, tamper detection, cleanup |
| `test/core/app_exception_test.dart` | Parsing the backend error envelope |
| `test/features/profile/profile_cubit_test.dart` | Profile loading and refresh |
| `test/widget_test.dart` | Widgets: step indicator, capture-guide geometry |

### Manual test checklist

Start from a clean backend (`rm -rf storage prisma/dev.db* && npm run setup && npm run dev`).

| Area | What to check |
|---|---|
| Auth | Weak password and duplicate email are rejected; wrong password shows *Invalid email or password*; the session survives killing the app; logout returns to login |
| Session | With a 30 s access token the app refreshes silently; with a 60 s refresh token and > 60 s idle, the next API call returns to login (see the backend README) |
| Details | Empty form shows an error on every required field; under 18, expired ID, expiry before issue date and a non-E.164 phone are rejected |
| Capture | Rectangle guide for the ID, oval for the selfie; retake and Gallery work; passports skip the back side; every photo ends as *uploaded* |
| Resume | Kill the app on any step → same step, same inputs and photos |
| Offline | Stop the server mid-flow → app keeps working, failed uploads show *Retry*; reopening shows the offline banner; start the server → *Retry* and the next edit sync again |
| Review | Each section can be edited; submit is disabled until consent is checked |
| Status | The three scenarios above; a pending application keeps polling after the app is reopened; an approved user opens straight on *My profile* |
| Security | With `PROTECT_SCREEN=true`, screenshots are blocked on Android and the app switcher shows no content |

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Android build fails in `camera_android_camerax` (`ListenableFuture` / `concurrent-futures`) | Already worked around in `android/build.gradle.kts`; run `flutter clean && flutter pub get` |
| "Cannot reach the server" on a USB Android phone | `adb reverse tcp:3000 tcp:3000` (again after reconnecting); check `<API_BASE_URL>/health` in the phone's browser |
| iPhone cannot reach the Mac | Same Wi-Fi, use `<Mac name>.local` or the Mac's IP, allow Node in the macOS firewall |
| Changes in `.env` have no effect | Stop the app and run it again (values are compiled in); make sure the run uses `--dart-define-from-file=.env` |
| Photos don't show after upload | `PUBLIC_BASE_URL` (backend) ≠ `API_BASE_URL` (app) |
| No camera on the iOS simulator | Use the **Gallery** button |
| Screenshots are black / screen recording is blank | `PROTECT_SCREEN=true` - set it to `false` only for the demo |
| Not sent back to login after the token expired | Expected until the next API call (pull to refresh, edit a field); tokens issued before changing the backend TTLs keep their old lifetime - log in again |
| *Retake Tester* was rejected | The name was typed as *Reject Tester*, or an already rejected account was reused - register a new email |
| Draft lost after updating the app from an old build | Older unencrypted drafts are discarded on purpose; the server draft is still restored |

## Possible next steps

Encrypt the cached photos and exclude them from iCloud backup, on-device quality checks before
upload (blur / glare detection, face detection with ML Kit), cropping the image to the guide
rectangle, push notifications or WebSocket instead of polling, localisation (vi / en), integration
tests with `patrol`, and certificate pinning.
