# ViraNari v1.3 — Live Safety

ViraNari v1.3 upgrades the hackathon prototype from a static SOS workflow into a resilient **live emergency tracking session** with a Find-My-style trusted-contact view and an SMS fallback path.

## What is implemented

### Victim app
- Press-and-hold SOS with real GPS.
- Active emergency session restored after app restart.
- Continuous GPS sampling during the active session (5-second target interval, no movement threshold).
- Android foreground emergency location notification.
- Local timestamps for **phone GPS fix** vs **last successful server sync**.
- Bounded encrypted queue for up to 120 unsynced location samples.
- Automatic replay of queued GPS points when API connectivity returns.
- Battery and connectivity state attached to location updates.
- Speed and heading attached when the device provides them.
- Trusted Circle delivery / acknowledgement counts.
- Practice mode.
- Resolve as safe / cancel false alarm.
- SMS fallback preparation before danger.
- Android SMS dispatch through the SIM when the API is unreachable.
- iOS SMS fallback opens the Messages composer; iOS does not silently send arbitrary SMS.

### Trusted Circle / responder app
- 3-second inbox refresh while the app is open.
- Find-My-style **Live Track** screen.
- In-app OpenStreetMap view with current marker and historical movement trail.
- LIVE / DELAYED / LAST SEEN freshness state.
- Keeps the last known marker when updates stop.
- Last update time displayed in the phone's local timezone.
- Accuracy, battery, network, speed and direction indicators.
- Call button when the sender has provided a phone number.
- Acknowledge button so the victim knows a real person is responding.

### Trusted phone privacy
- Users own and update their own E.164 phone number (`+countrycode...`).
- A contact's phone number is **not disclosed while an invitation is pending**.
- Phone number becomes available only after that user explicitly accepts the Trusted Circle relationship.
- Active trusted phone numbers are cached in encrypted device storage so SMS fallback can still work when mobile data is unavailable.

### Backend
- FastAPI + SQLAlchemy + SQLite for the hackathon build.
- Argon2 password hashing.
- JWT authentication.
- Persistent 64-character development JWT secret is generated automatically if `VIRANARI_JWT_SECRET` is not provided.
- UTC-safe API serialization so Flutter can convert timestamps correctly to IST / local device time.
- Explicit compatibility migrations for v1/v1.2 SQLite databases.
- Audit events and API rate limiting inherited from v1.2.
- 22 backend tests.

## Important limitations

This is a hackathon prototype, not a certified emergency-service product.

- No Firebase/APNs push yet. Recipient live updates are automatic while ViraNari is running/open.
- Android direct SMS depends on SIM/service and `SEND_SMS` permission. SMS is not internet-free if there is no cellular network at all.
- iOS does not silently send SMS; ViraNari opens the Messages composer for the user to approve.
- OpenStreetMap tiles on the responder Live Track screen require network access unless an offline map layer is added later.
- Background location behavior still depends on Android/iOS power-management policies and permissions.
- ViraMesh/BLE multi-hop relay is **not** implemented in v1.3.

---

## Backend — local/VPS

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python run.py
```

Default backend port is **3000**.

Health:

```bash
curl http://127.0.0.1:3000/health
```

Docs:

```text
http://127.0.0.1:3000/docs
```

For a VPS behind Nginx:

```env
VIRANARI_HOST=127.0.0.1
VIRANARI_PORT=3000
VIRANARI_DB_PATH=/root/Viranari/backend/data/viranari.db
VIRANARI_JWT_SECRET=<64+ character random secret>
```

For a quick direct-port test you can use `VIRANARI_HOST=0.0.0.0`, but production should normally expose HTTPS through Nginx and leave Uvicorn bound to localhost.

---

## Flutter — first setup on Arch/fish

From project root:

```fish
./scripts/prepare_mobile.fish
```

Then start an emulator and run:

```fish
cd mobile
flutter devices
flutter run --dart-define=VIRANARI_API_BASE=http://10.0.2.2:3000
```

Against your VPS API:

```fish
flutter run --dart-define=VIRANARI_API_BASE=https://api.example.com
```

For a temporary direct-IP test:

```fish
flutter run --dart-define=VIRANARI_API_BASE=http://YOUR_VPS_IP:3000
```

Use HTTPS for the final demo/release.

## Before testing SMS

1. Register both users with international-format numbers, e.g. `+919876543210`.
2. Invite and accept the Trusted Circle relationship.
3. Open the sender's Trusted Circle screen once while online so accepted numbers are securely cached.
4. On Home enable **Prepare SMS fallback before danger** and grant the Android SMS permission.
5. For a test, use Practice Mode first. Practice Mode deliberately does **not** send SMS.
6. For a real transport test, use test phone numbers / team devices only.

## Find-My-style tracking test

On sender phone:
1. Start SOS.
2. Grant location permission; for strongest background behavior use `Allow all the time` where available.
3. Move the emulator GPS coordinates or physically walk with the phone.
4. Home should show changing `Phone GPS fix` and `Server synced` times.

On trusted-contact phone:
1. Open Inbox.
2. Tap **Live Track**.
3. Marker/trail refreshes every 3 seconds while the screen is open.
4. Stop sender connectivity: status eventually changes from LIVE → DELAYED → LAST SEEN while preserving the last known marker.
5. Restore internet: queued sender points replay to the server.

## Backend tests

```bash
cd backend
pytest -q
```

Expected for this source release:

```text
22 passed
```

See `UPGRADE_FROM_V1_2.md` before replacing an existing VPS deployment.
