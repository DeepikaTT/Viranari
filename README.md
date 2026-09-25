# ViraNari v1.2 — victim-first emergency-response prototype

ViraNari v1.2 is the continuation of v0.1 through the v1.1/v1.2 milestone. The demo is designed around one principle: **during danger, the user should make as few decisions as possible.**

## What works now

### V1 core
- Secure register/login (Argon2 password hashing + signed bearer tokens)
- Consent-based Trusted Circle invitations
- Press-and-hold SOS with haptic feedback
- Real GPS capture
- Persistent emergency records
- SENT → DELIVERED → ACKNOWLEDGED delivery states
- Recipient Emergency Inbox
- Offline encrypted retry queue with idempotency protection
- SOS history and contact removal

### V1.1 reliability + UX
- Brand refresh: deep teal, lotus pink, antique gold, warm ivory
- Connectivity and backend-reachability status
- Battery percentage + low-battery warning
- Better emergency-state dashboard
- Immediate SOS activation; false-alarm cancellation does **not** delay a real alert
- Practice/Test mode with clear TEST labels
- Error/retry UX
- Backend audit events
- Simple per-user request throttling for SOS/location update endpoints
- Updated fish scripts with proper error handling

### V1.2 live emergency session
- One active emergency session restored after app restart
- Live location stream during an active emergency
- Android foreground location notification so live tracking can continue when the sender app moves to the background, subject to OS permissions/power policy
- Latest location, battery, and network state sent to backend
- Location timeline stored on the server
- Trusted-contact inbox auto-refreshes every 5 seconds while app is running
- Multiple trusted contacts receive the same SOS
- Recipient acknowledgement visible to sender
- Recipient can open latest coordinates in installed Maps app
- "I'm safe — end emergency" state
- "Cancel false alarm" state retained in audit/history

## Important external integration not falsely claimed

True **background recipient push notifications** require a configured push provider (Firebase Cloud Messaging for Android and APNs/Firebase for iOS) plus project credentials. This source intentionally does not pretend push is working without those credentials. The current recipient app auto-refreshes while running; push is the next production integration.

## Run on Arch + fish

### Terminal 1 — backend

```fish
cd viranari_v1_2
./scripts/setup_backend.fish
./scripts/run_backend.fish
```

Health check:

```fish
curl http://127.0.0.1:8000/health
```

Swagger:

`http://127.0.0.1:8000/docs`

Run backend tests:

```fish
./scripts/test_backend.fish
```

### Terminal 2 — mobile

```fish
cd viranari_v1_2
./scripts/prepare_mobile.fish
flutter emulators
flutter emulators --launch Pixel_7
cd mobile
flutter run --dart-define=VIRANARI_API_BASE=http://10.0.2.2:8000
```

For a physical Android phone, `10.0.2.2` will not point to the laptop. Put both devices on the same Wi-Fi and run with your laptop LAN IP, for example:

```fish
flutter run --dart-define=VIRANARI_API_BASE=http://192.168.1.50:8000
```

The backend already listens on `0.0.0.0:8000`.

## Demo flow

1. Register Person A and Person B.
2. A invites B from Trusted Circle; B accepts the consent code.
3. A holds SOS.
4. A's GPS + battery + network state are recorded; the emergency becomes ACTIVE immediately.
5. B's Inbox sees the alert (auto-refresh while app is running) and can open the latest point in Maps.
6. Move A's emulator GPS or physical phone; new live points are added to the server timeline.
7. B acknowledges the alert.
8. A sees acknowledgement count update.
9. A uses **I'm safe — end emergency** when safe.
10. Repeat in Practice Mode for a judge-safe test alert.

## Database

The run script uses `backend/data/viranari_v12.db`, intentionally separate from v0.1 so an old prototype database cannot break the new v1.2 schema.

## Safety engineering choices

- No pre-SOS countdown: accidental triggers can be cancelled **after** the alert is created, so help is never delayed by a timer.
- No fake "message delivered" state: delivery is recorded only when the recipient inbox retrieves the alert.
- No fake push notification claim without Firebase/APNs credentials.
- Location sharing is scoped to active emergency sessions rather than permanent tracking.
- Trusted contacts require consent.
- Practice alerts are visibly labelled TEST.

See `VICTIM_FIRST_ROADMAP.md` for the next safety-network ideas.
