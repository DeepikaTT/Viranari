# ViraNari V1.4 — Reliable Response

V1.4 turns the V1.3 Live Safety prototype into a more reliable, less cluttered emergency-response build. The central change is architectural: **device liveness is now separate from GPS freshness**. A victim who is standing still can remain LIVE because the phone sends heartbeats even if its coordinates do not change.

## Implemented in V1.4

### Reliable live safety
- Heartbeat endpoint and client heartbeat every ~10 seconds while an SOS is active.
- Separate timestamps for:
  - last device heartbeat,
  - last GPS fix,
  - last successful location sync.
- Responder status uses heartbeat rather than GPS movement:
  - LIVE: recent device heartbeat,
  - DELAYED: heartbeat late,
  - OFFLINE: heartbeat missing.
- GPS freshness is displayed separately, so **stationary != disconnected**.
- Forced GPS refresh when the position stream is quiet for too long.
- Location stream automatically restarts after errors/completion.
- Immediate heartbeat + fresh GPS + queue replay after connectivity recovery.
- Offline GPS points retain their original capture timestamps.
- Sender does not repeatedly hammer the API while it already knows the backend is offline; points are queued locally instead.
- Moving route trail, direction, speed, accuracy and distance travelled on the responder map.

### SMS fallback reliability
- Internet/API remains first transport.
- During an active SOS, sustained API loss can trigger one fallback SMS per outage.
- Failed SMS preparation does not permanently suppress retry for the whole outage.
- Retry attempts are throttled to avoid SMS spam.
- Android checks:
  - SEND_SMS permission,
  - telephony/SMS capability,
  - SIM readiness,
  - default SMS subscription selection.
- A **real TEST SMS** action is available from Safety Controls so the transport can be checked before danger.
- SMS includes a maps link, time and battery information.
- iOS uses the system Messages composer; iOS does not permit arbitrary silent SMS sending.

### Journey Guard
- Start a safety journey with a destination label and expected travel time.
- Only one active Journey Guard session per user.
- Trusted Circle members can see active journeys in the Response tab.
- Missed expected arrival is calculated server-side and shown as **OVERDUE**.
- User can mark the journey safe or cancel it.
- Journey Guard does not fabricate an SOS automatically; it creates a visible missed-check-in signal for trusted people.

### Safety Presence
- Optional nearby-device radar.
- Presence is opt-in and short-lived.
- Exact presence coordinates are not persisted; server stores quantised coordinates only.
- Nearby API returns no user name, phone number, account ID, or stable public identifier.
- Client sees only approximate distance, coarse bearing and freshness.
- Presence expires logically after 120 seconds without an update.
- This is internet-backed presence in V1.4. It is **not ViraMesh/BLE** yet.

### Cleaner UI
- Home is centered around the SOS control rather than stacked feature cards.
- Compact top status strip for server/network/battery/trusted-circle state.
- Journey Guard appears as a slim status strip only when active.
- Secondary features are three compact actions: Journey, Nearby, SMS Setup.
- Technical diagnostics are hidden under an expandable section.
- Trusted Circle and History are flat list layouts rather than card stacks.
- Response screen uses a flat emergency list.
- Live Track uses the map as the main surface with compact floating status/action panels.

## Backend

- FastAPI
- SQLAlchemy
- SQLite for the hackathon prototype
- Argon2 password hashing
- JWT authentication
- request throttling
- audit events
- idempotent SOS creation
- compatibility migrations for V1/V1.2/V1.3 SQLite databases
- 33 automated backend tests

### Run locally / on VPS

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python run.py
```

Default port: `3000`.

```bash
curl http://127.0.0.1:3000/health
```

Swagger:

```text
http://127.0.0.1:3000/docs
```

For production-style VPS deployment, keep Uvicorn on `127.0.0.1:3000` behind Nginx/HTTPS. For a temporary direct-port demo, `0.0.0.0:3000` can be used with the firewall configured appropriately.

## Flutter setup on Arch / fish

From project root:

```fish
./scripts/prepare_mobile.fish
cd mobile
flutter analyze
```

Android emulator + local backend:

```fish
flutter run --dart-define=VIRANARI_API_BASE=http://10.0.2.2:3000
```

VPS:

```fish
flutter run --dart-define=VIRANARI_API_BASE=https://api.example.com
```

Temporary direct-IP test:

```fish
flutter run --dart-define=VIRANARI_API_BASE=http://YOUR_VPS_IP:3000
```

Re-run `prepare_mobile.fish` when using this source package because V1.4 patches Android SMS capability checks and platform permissions.

## Physical-device live tracking test

1. Device A and Device B sign in to separate ViraNari accounts.
2. A invites B; B accepts.
3. A starts SOS.
4. B opens Response → Track.
5. Keep A stationary for 60+ seconds.
   - B should remain LIVE while heartbeats arrive.
   - GPS age may increase independently.
6. Walk with A.
   - marker and trail should update,
   - distance travelled should increase.
7. Disable Wi-Fi **and mobile data** on A while leaving cellular/SMS service available.
   - GPS points should queue locally,
   - B transitions LIVE → DELAYED → OFFLINE,
   - last location remains visible,
   - SMS fallback can run if prepared.
8. Restore internet.
   - A sends a heartbeat immediately,
   - queued GPS trail replays,
   - fresh GPS is published,
   - B returns to LIVE.

Turning Wi-Fi off alone may simply cause Android to switch to mobile data, so that is not a valid SMS-fallback outage test.

## SMS test checklist

Use a physical Android phone. The emulator cannot validate carrier SMS.

- physical SIM/eSIM can send SMS,
- airplane mode off,
- default SMS SIM selected on dual-SIM phones,
- ViraNari SMS permission granted,
- both users have `+countrycode...` phone numbers,
- Trusted Circle invitation accepted,
- sender opened Trusted Circle while online so numbers were cached,
- Safety Controls → SMS fallback enabled,
- use **Send a real TEST SMS** before testing outage fallback.

## Current limitations

V1.4 is a hackathon prototype, not a certified emergency-service product.

- No Firebase/APNs push notification service yet.
- Journey Guard overdue status becomes visible when trusted users refresh/poll the app; it is not yet a push alarm.
- Safety Presence is server-backed and app-open/periodic; ViraMesh BLE presence is planned for V2.
- OpenStreetMap tiles require data unless an offline map package is added.
- iOS background behavior differs from Android and needs device/TestFlight testing.
- Verified Safe Nodes and Safety Compass are planned next, not faked in this release.

See `UPGRADE_TO_V1_4.md`, `DEMO_CHECKLIST.md`, and `V1_4_FEATURES_FOR_PPT.md`.
