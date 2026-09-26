# ViraNari V1.8.1 — Live Coordination

V1.8 keeps the SOS, Silent Safety Session, Trusted Circle, Safety Map, Safety Compass, Open Map and Live Track core, then focuses on **live movement and responder coordination**. It intentionally does **not** add an emergency timeline and does **not** include CCTV/camera-surveillance features.

## New in V1.8

### 1. Safety Map radius filters actually filter
The **500 m / 2 km / 5 km** selector now controls:
- the anonymous-presence backend query;
- the visible anonymous dots;
- visible Safe Nodes/public safety places;
- the map zoom;
- the counts shown under the map.

Public safety places can still be cached from OpenStreetMap when no operator-verified ViraNari Safe Nodes are available. They remain clearly labelled **not ViraNari verified**.

### 2. Victim ↔ responder live GPS distance
A trusted contact taps **I'm responding** in Live Track. ViraNari then:
- acknowledges the SOS;
- starts sharing that responder's exact GPS only inside that active trusted SOS;
- shows **both victim and responder markers**;
- recomputes straight-line distance every few seconds;
- shows an **Approx ETA** using current responder speed when available, otherwise a conservative walking pace;
- sends the victim the acknowledged responder's latest position, distance and ETA.

Exact responder coordinates are never added to the anonymous Safety Map.

### 3. Visible live GPS changes
Live Track now exposes the newest coordinates and update time directly:
- current victim latitude/longitude;
- latest GPS-change age;
- route trail;
- direction, accuracy and battery;
- responder distance and approximate ETA when accepted.

The sender still uses the V1.4-style heartbeat/GPS/server-sync separation, so standing still does not mean disconnected.

### 4. Incoming SOS full-screen alert
While ViraNari is running, the Trusted Circle is polled every few seconds. A new unacknowledged SOS opens a non-dismissible full-screen emergency alert that:
- pulses visually;
- repeats haptic attention cues;
- shows Silent SOS clearly;
- stays until **ACCEPT & OPEN LIVE TRACK** succeeds.

This is a hackathon-ready in-app alert path. Reliable delivery when the app is fully killed requires a real push service such as FCM/APNs and is intentionally not falsely claimed here.

### 5. Android Emulator demo helpers
No physical GPS hardware is required for the demo. Included scripts:

```fish
./scripts/emulator_prepare_demo.fish
./scripts/emulator_route_demo.fish
```

The first grants runtime permissions to the emulator through ADB, avoiding manual permission tapping. The second injects a moving GPS route into the emulator so the live marker/trail can visibly change. Production phones still require normal Android user permission consent.

## Existing core retained
- press-and-hold normal SOS;
- hold ViraNari shield for Silent Safety Session;
- continuous emergency GPS (`distanceFilter: 0`);
- heartbeat-based LIVE / DELAYED / OFFLINE;
- Android foreground emergency tracking;
- offline GPS queue and reconnect replay;
- Trusted Circle consent;
- Sent / Delivered / Acknowledged state;
- Inbox and History;
- external Open Map;
- anonymous Safety Map;
- Safety Compass;
- Practice Mode;
- false-alarm cancellation and I'm Safe resolution.

## Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python run.py
```

Health:

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.8.1`.

Backend automated validation for this package: **36 tests passed**.

## Mobile

```fish
./scripts/prepare_mobile.fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
```

Run against your server:

```fish
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR_API_DOMAIN
```

## Two-user live coordination demo

1. Phone A starts SOS.
2. Phone B receives the full-screen incoming alert while ViraNari is running.
3. B taps **ACCEPT & OPEN LIVE TRACK**.
4. B taps/uses responder GPS; the Live Track screen shows victim + responder positions.
5. Move either device (or inject emulator movement).
6. Watch coordinates, marker position, distance and Approx ETA update.
7. On A, the emergency card shows the acknowledged responder's latest GPS/distance/ETA.

## Prototype boundary

ViraNari V1.8 is a hackathon prototype, not a certified dispatch system. Full killed-app notification delivery needs a push provider; ETA is approximate rather than road-routing ETA; public OpenStreetMap safety places are not ViraNari-verified unless explicitly added and verified by the operator.
