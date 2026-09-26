# ViraNari V1.5.0 — SafeReach + ProofChain

V1.5.0 is an additive release built directly on the V1.4.4 product surface. It keeps the V2-style UI, V4 reliable location engine, Trusted Circle, Emergency Inbox, History, offline retry, visible coordinates, external Open Map flow, and the expanded live location timeline.

## What stays locked from V1.4.4

- Home / Circle / Inbox / History navigation.
- Press-and-hold SOS.
- Continuous emergency location tracking using the V1.4 engine.
- `distanceFilter: 0`, Android `bestForNavigation`, requested ~5-second updates.
- Separate device heartbeat, GPS freshness and server-sync state.
- Forced GPS recovery and stream restart.
- Offline location queue + reconnect replay with original timestamps.
- Trusted Circle consent, delivery state and acknowledgement.
- GPS coordinates visible directly in emergency cards.
- `Open map` launches the latest point in the installed map app.
- **Live location timeline** shows every stored location record, newest first, and refreshes every 5 seconds.
- SMS remains a placeholder only in this release; no SMS permission is requested.
- No Nearby/Safety Presence and no Journey Guard.

## New: SafeReach verified emergency help

When an SOS reaches the backend, SafeReach can automatically route it to the nearest responder who is:

1. admin-verified,
2. marked available,
3. recently online,
4. inside the responder's configured service radius.

The responder can accept, mark arrival and complete the response. Unanswered offers expire after the configured timeout and SafeReach escalates to the next eligible verified responder. The traveler and Trusted Circle can see the responder organization, category, approximate match distance and current response state.

V1.5.0 deliberately does **not** expose SOS incidents to random nearby users.

## New: ProofChain cryptographic incident record

Important incident actions are stored in a per-emergency SHA-256 hash chain and signed by a persistent Ed25519 backend key. Changing a historical event breaks verification.

Signed actions include:

- SOS creation / test drill creation,
- Trusted Circle notification,
- first delivery confirmation,
- Trusted Circle acknowledgement,
- SafeReach responder match / no-match,
- responder accept / arrive / complete / decline,
- live location fixes,
- offline location batch replay,
- SOS resolution / cancellation.

This is **tamper-evident**, not a claim that the database is physically impossible to alter.

Endpoints:

- `GET /proof/public-key`
- `GET /alerts/{alert_id}/proof`
- `GET /alerts/{alert_id}/proof/verify`

The mobile SafeReach sheet displays integrity state, signed event count, key ID and recent incident actions.

## Calling restored

During an active SOS the sender now has one-tap actions to:

- open the system dialer for the first accepted Trusted Circle contact with a phone number,
- open the system dialer for emergency services,
- call the matched SafeReach responder when a phone number is available.

Trusted contacts can also call the sender directly from Emergency Inbox.

The default emergency number is `112`; override it at build/run time:

```fish
--dart-define=VIRANARI_EMERGENCY_NUMBER=112
```

## Verified responder setup

Responders first create a normal ViraNari account. An administrator then verifies that account using the server-side admin key.

Add to `backend/.env`:

```dotenv
VIRANARI_ADMIN_KEY=replace-with-a-long-random-admin-key
VIRANARI_PROOF_KEY_PATH=./data/.proof_ed25519.pem
VIRANARI_RESPONDER_LOCATION_TTL_MINUTES=30
VIRANARI_RESPONDER_OFFER_TIMEOUT_SECONDS=60
```

Example verification:

```bash
curl -X POST https://YOUR_API_DOMAIN/admin/responders/verify \
  -H 'Content-Type: application/json' \
  -H 'X-ViraNari-Admin-Key: YOUR_ADMIN_KEY' \
  -d '{
    "user_email":"security@example.com",
    "organization_name":"Campus Security Gate 2",
    "category":"campus_security",
    "service_radius_m":5000,
    "latitude":17.385,
    "longitude":78.4867,
    "is_available":true
  }'
```

After verification, sign out and sign back in on the responder phone so the refreshed account role enables **Responder console** in the app menu.

## Upgrade existing VPS without losing data

Preserve these before replacing source:

- `backend/.env`
- `backend/data/viranari.db`
- your virtual environment if desired

V1.5.0 performs an idempotent compatibility migration that adds the user role column; the responder, assignment and ProofChain tables are created automatically. Existing V1.4.4 alerts and location history remain intact.

```bash
cd /root/Viranari/backend
source venv/bin/activate   # or .venv/bin/activate
pip install -r requirements.txt
python run.py
```

Verify:

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.5.0`.

## Prepare mobile wrapper

From the repository root:

```fish
./scripts/prepare_mobile.fish
cd mobile
flutter clean
rm -rf .dart_tool build
flutter pub get
flutter analyze
```

`prepare_mobile.fish` now also deletes Flutter's default `test/widget_test.dart`, so the old `MyApp` smoke-test error should not reappear.

Run against the VPS:

```fish
flutter run \
  --dart-define=VIRANARI_API_BASE=https://YOUR_API_DOMAIN \
  --dart-define=VIRANARI_EMERGENCY_NUMBER=112
```

Build release APK:

```fish
flutter build apk --release \
  --dart-define=VIRANARI_API_BASE=https://YOUR_API_DOMAIN \
  --dart-define=VIRANARI_EMERGENCY_NUMBER=112
```

## Demo flow

1. Traveler + Trusted Contact + Responder each register.
2. Admin verifies the responder account.
3. Responder opens **Responder console**, turns availability on and refreshes current location.
4. Traveler holds SOS.
5. Trusted Contact sees Emergency Inbox + live location timeline.
6. SafeReach automatically selects the nearest eligible verified responder.
7. Responder accepts, then marks arrival.
8. Traveler and Trusted Contact open **SafeReach** and see responder status.
9. Open the ProofChain section: integrity should show **verified**.
10. Continue moving: the old V1.4.4 location timeline continues collecting records.

## Validation performed in packaging environment

Backend tests: **35 passed**.

The packaging environment does not contain Flutter, so Android compilation and `flutter analyze` must still be run on your Arch/CachyOS development machine before treating the APK as release-ready.
