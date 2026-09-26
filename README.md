# ViraNari V1.6.0 — Resilient Commute

V1.6.0 keeps the V1.4.4 product surface and V4 live-tracking engine, then makes the emergency communication flow more useful in the real world.

## Preserved from V1.4.4 / V1.5.0

- V2-style Home / Circle / Inbox / History UI.
- Hold-to-activate SOS and practice mode.
- Trusted Circle consent and acknowledgement.
- V4 continuous emergency tracking (`distanceFilter: 0`, best-for-navigation, requested ~5-second Android interval).
- Device heartbeat separated from GPS freshness.
- Forced GPS refresh, reconnect handling, visible coordinates and external Open Map.
- Full live-location timeline with every server-stored point.
- SafeReach verified responder backend and responder console.
- Ed25519 + SHA-256 tamper-evident incident record.
- No Nearby/Presence and no Journey Guard.

## Fixed: phone-number onboarding

V1.5 had call buttons but registration did not collect a phone number. V1.6 fixes that gap.

- New accounts must enter a mobile number in E.164 format, e.g. `+919876543210`.
- Existing accounts can add or edit their own emergency phone number from **Circle**.
- A trusted contact's number is revealed only after the invitation has been accepted.
- Active contacts show whether a usable phone number is available.
- **Call trusted** now lets the traveler choose among multiple callable trusted contacts instead of silently choosing the first one.

## New: practical SMS fallback without SEND_SMS permission

During an active SOS, **SMS fallback** opens the phone's normal Messages app with a trusted contact and an emergency message pre-filled. The message contains:

- trip/incident ID,
- latest latitude and longitude,
- capture time,
- GPS accuracy,
- battery level,
- a map link,
- an emergency instruction.

This can work with mobile data turned off as long as normal cellular SMS service exists. ViraNari does **not** claim the message was sent: the user confirms Send in the system Messages app. This avoids Android `SEND_SMS` permission and Google Play SMS-role restrictions.

Trusted phone numbers are cached in encrypted device storage after a successful Circle sync, so Call/SMS fallback can still find them when the API becomes unreachable.

## New: durable multi-day offline GPS journal

V1.5's emergency location queue was capped at 120 points. At a five-second cadence that was only about ten minutes.

V1.6 moves queued emergency GPS points into a local SQLite journal and retains up to 100,000 records, roughly 5.8 days at a strict five-second cadence. When connectivity returns, existing batched replay uploads the original timestamps.

The home status panel now shows how many GPS points are waiting to sync.

## SafeReach is now positioned correctly

SafeReach is retained as **Verified Help**, but it is not presented as a replacement for Trusted Circle, calling or SMS. It is useful only where an approved responder network such as campus security, hostel security, a clinic or another partner organization is actually enrolled and online.

If no responder is available, Trusted Circle, location tracking, call actions and SMS fallback continue normally.

## Incident Record instead of technical ProofChain-first UX

History now exposes **Incident record**. The sheet still cryptographically verifies the signed hash-chain, but the primary view is a human-readable incident timeline such as:

- SOS started
- Trusted Circle notified
- location captured
- trusted contact acknowledged
- SMS fallback prepared
- trusted-contact call opened
- verified responder matched / accepted / arrived
- offline route recovered
- emergency resolved

The cryptographic integrity result remains visible underneath. V1.6 also records SMS-composer preparation and dialer-open actions on the signed incident record when the backend is reachable. These events deliberately say `PREPARED`/`DIALER_OPENED`; they do not falsely claim an SMS was delivered or a call connected.

## Backend tests

`38 passed` in the package-generation environment.

## Prepare mobile

```fish
cd ~/Projects/Viranari
./scripts/prepare_mobile.fish
cd mobile
flutter clean
rm -rf .dart_tool build
flutter pub get
flutter analyze
```

Then run:

```fish
flutter run \
  --dart-define=VIRANARI_API_BASE=https://YOUR_API_DOMAIN \
  --dart-define=VIRANARI_EMERGENCY_NUMBER=112
```

## VPS upgrade

Preserve:

- `backend/.env`
- `backend/data/viranari.db`
- `backend/data/.proof_ed25519.pem`

Then install the new requirements and restart the backend.

```bash
cd /root/Viranari/backend
source venv/bin/activate
pip install -r requirements.txt
pm2 restart viranari --update-env
curl http://127.0.0.1:3000/health
```

Expected health version: `1.6.0`.
