# ViraNari v0.1 — Working Hackathon Prototype

ViraNari v0.1 is an Android-first Flutter app plus FastAPI backend built around one end-to-end promise: an SOS is not called **delivered** until a trusted contact app retrieves it, and is not called **acknowledged** until that trusted contact explicitly confirms it.

## What is implemented now

- Account registration/login with Argon2 password hashing and signed access tokens.
- Consent-based Trusted Circle: the recipient must already have an account and explicitly accept an invite code.
- Real GPS capture on SOS using the phone location service.
- Press-and-hold SOS with haptic confirmation to reduce accidental triggers.
- Persistent backend emergency records in SQLite/WAL mode.
- Idempotent SOS creation so retries cannot create duplicate emergencies.
- Encrypted-at-rest local retry queue using Android/iOS secure storage.
- Timeout reconciliation: before retrying an uncertain POST, the app checks whether the server already received the same idempotency key.
- Trusted-contact emergency inbox while the app is open.
- Delivery receipt when the trusted contact inbox retrieves the alert.
- Explicit trusted-contact acknowledgement, visible to the sender.
- SOS history with sent/delivered/acknowledged state.
- Contact removal: removed contacts do not receive future SOS events.
- 10 backend tests covering authentication, consent, retries, access control, acknowledgement, removal, and persistence.

## Deliberately not faked in v0.1

BLE mesh, background push notifications, offline maps, and compass navigation are **not** represented as working features yet. They are the next milestones. The current build is honest and demonstrable end-to-end.

## Architecture

```text
Flutter Android app
  ├─ real GPS
  ├─ secure session token
  ├─ secure offline SOS queue
  ├─ Trusted Circle
  ├─ emergency inbox
  └─ SOS history
          │ HTTPS/HTTP in local demo
          ▼
FastAPI API
  ├─ auth
  ├─ trusted-contact consent
  ├─ idempotent emergency creation
  ├─ delivery receipts
  ├─ acknowledgement
  └─ SQLite persistence
```

## 1. Start the backend on Arch + fish

From the extracted project root:

```fish
./scripts/setup_backend.fish
./scripts/run_backend.fish
```

The backend listens on:

```text
http://0.0.0.0:8000
```

Health check:

```fish
curl http://127.0.0.1:8000/health
```

Swagger UI is available locally at `/docs`.

## 2. Generate Flutter Android/iOS wrappers

The source package intentionally keeps generated platform wrappers out of the archive so your installed Flutter 3.47.5 creates wrappers that match your machine.

```fish
./scripts/prepare_mobile.fish
```

This command:

1. runs `flutter create` for Android and iOS,
2. restores the ViraNari source files,
3. adds Android INTERNET + location permissions,
4. enables cleartext HTTP only for local hackathon development,
5. adds the iOS location usage description,
6. runs `flutter pub get`.

## 3. Run on your Android emulator

Your Android emulator reaches the host computer through `10.0.2.2`:

```fish
cd mobile
flutter devices
flutter run --dart-define=VIRANARI_API_BASE=http://10.0.2.2:8000
```

The default in the source is already `http://10.0.2.2:8000`, so plain `flutter run` also works for the standard Android emulator.

## 4. Run on a physical Android phone

The phone and laptop must be on the same network. Find the laptop LAN address, for example:

```fish
ip -br addr
```

If the laptop address is `192.168.1.50`, run:

```fish
flutter run --dart-define=VIRANARI_API_BASE=http://192.168.1.50:8000
```

Do not use `10.0.2.2` on a physical phone; that special address is for the Android emulator.

## 5. Exact two-account demo flow

Use two accounts so the delivery/acknowledgement story is real.

**Phone/emulator A — person sending SOS**

1. Create `asha@example.com`.
2. Open Trusted Circle → Invite.
3. Enter the registered email of Phone B.
4. Copy the generated consent code.

**Phone/emulator B — trusted contact**

1. Create `maya@example.com`.
2. Open Trusted Circle → Accept code.
3. Paste the code from A.

**Emergency demo**

1. On A, press and hold the SOS button.
2. Allow location permission.
3. A shows **Sent** — not Delivered yet.
4. On B, open Emergency Inbox / pull to refresh.
5. A can refresh and now shows **Delivered**.
6. On B, tap **I received this — acknowledge**.
7. Refresh A; status becomes **Acknowledged**.

That state transition is a strong judging point because the UI does not falsely claim that a contact was notified.

## 6. Offline retry demo

1. Keep A signed in and with an active trusted contact.
2. Stop the backend or disconnect the phone from the network.
3. Trigger SOS after GPS is obtained.
4. The encrypted local queue records the attempt.
5. Restore connectivity/backend.
6. Pull-to-refresh Home or reopen the Home screen.
7. ViraNari first reconciles the idempotency key and then safely retries only if the server does not already have that SOS.

This handles the difficult case where the phone timed out even though the server may have accepted the original request.

## 7. Run backend tests

```fish
cd backend
source .venv/bin/activate.fish
PYTHONPATH=. pytest -q
```

Expected:

```text
10 passed
```

## Development-only security note

`android:usesCleartextTraffic="true"` is inserted only to make laptop-to-phone local HTTP testing simple. For a deployed build, put the API behind HTTPS and remove cleartext traffic. Replace `VIRANARI_JWT_SECRET` with a random long secret before any public deployment.

## v0.2 priority after this works on two phones

1. BLE peer discovery and one-hop encrypted SOS relay on two physical Android phones.
2. Background notification delivery (FCM/APNs) so the trusted contact does not need the inbox open.
3. Offline cached safe-location data and Safety Compass.
4. Multi-hop store-and-forward packet TTL, replay protection, rotating node IDs.
5. On-device multilingual intent commands only after the emergency transport path is stable.
