# ViraNari V1.4.2 — Core Restore

V1.4.2 deliberately rolls the product surface back toward the cleaner V1.3 experience while keeping the reliable live-location engine introduced later.

## What this version keeps

- Press-and-hold SOS
- Consent-based Trusted Circle
- Delivery and acknowledgement states
- Find-My-style live map
- Device heartbeat independent from GPS movement
- Continuous GPS stream with `distanceFilter: 0`
- Android target interval of ~5 seconds during an active emergency
- Forced fresh GPS request if the stream stays quiet for ~8 seconds
- Background Android location foreground service
- Live route trail, speed, heading, distance travelled and accuracy
- Last-known location when a device disconnects
- Offline GPS queue with original timestamps
- Immediate reconnect health check and queued-location replay
- Persistent SOS history
- Practice mode
- False-alarm cancellation and "I'm safe" resolution

## What was removed

- Journey Guard
- Safety Presence / nearby-device radar
- SMS fallback and all SEND_SMS native permission code

Those features are intentionally out of this build so the emergency core can be tested without unrelated UI or platform-permission failures.

## UI direction

V1.4.2 restores the calmer V1.3-style Home screen: status chips, one dominant SOS control, one live-location status surface, and one emergency-session surface. The map remains a first-class bottom-navigation destination.

Bottom navigation:

`Home · Map · Circle · Inbox`

SOS history is available from the top-right menu.

## Backend

FastAPI + SQLAlchemy + SQLite for the prototype. Existing V1.4.x databases are compatible; unused legacy tables such as `safety_presence_devices` may remain in an upgraded SQLite file but are no longer exposed by the API.

Health check:

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.4.2`.

## Run backend

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python run.py
```

## Prepare mobile wrapper on Arch/fish

```fish
./scripts/prepare_mobile.fish
cd mobile
flutter clean
flutter pub get
flutter analyze
```

Run against a VPS:

```fish
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR-API-DOMAIN
```

or temporarily:

```fish
flutter run --dart-define=VIRANARI_API_BASE=http://YOUR-VPS-IP:3000
```

## Priority physical-phone test

1. Trigger SOS on Phone A.
2. Phone B opens Map or Inbox -> Live Track.
3. Leave Phone A stationary for at least one minute: it should remain LIVE because heartbeat is separate from GPS movement.
4. Walk with Phone A: marker/trail should move and distance should increase.
5. Disable data/Wi-Fi on Phone A: Phone B eventually shows DELAYED/OFFLINE but keeps the last marker.
6. Re-enable connectivity: Phone A should heartbeat immediately, replay queued GPS points and return to LIVE.

