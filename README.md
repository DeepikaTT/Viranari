# ViraNari V1.5.0 — Safety Around Me

V1.5 keeps the V1.4.3 emergency core and adds three focused differentiators without removing SOS, Trusted Circle, Open Map, Live Track, Inbox or History.

## New in V1.5

### 1. Safety Map
A full-screen map shows:
- **YOU** at the phone's real current location.
- **Anonymous pink dots** for opted-in nearby ViraNari installations.
- **Shield markers** for operator-verified Safe Nodes.

Privacy rules:
- nearby users are mutual opt-in;
- the backend stores coarsened presence coordinates;
- nearby responses expose only approximate distance, bearing and age;
- no name, email, phone number, user ID, device ID or exact nearby-user coordinate is returned;
- presence expires quickly when a phone stops broadcasting.

The normal bottom navigation remains **Home · Circle · Inbox · History**. Safety Map is opened contextually from Home, so the V1.4.3 interaction model remains intact.

### 2. Silent Safety Session
Hold the ViraNari **shield logo** in the app bar to start a Silent SOS.
- two short haptic confirmations;
- GPS, heartbeat, Trusted Circle delivery and live tracking start exactly like normal SOS;
- the sender screen suppresses obvious red emergency UI until the session is revealed;
- responders see a clear **SILENT SOS** label and are warned the sender may be unable to speak/type/use the phone visibly;
- holding the shield again, or holding the normal SOS control, reveals the active session so it can be resolved/cancelled.

### 3. Safety Compass
The compass points toward a verified Safe Node using:
- current GPS;
- device compass heading;
- distance and bearing calculations;
- cached Safe Nodes if the network later disappears.

ViraNari never invents a Safe Node. Server operators must add and verify real physical places with `backend/manage_safe_nodes.py`.

## Core features retained
- press-and-hold SOS;
- heartbeat-based LIVE / DELAYED / OFFLINE state;
- continuous emergency GPS with `distanceFilter: 0`;
- background foreground-service location tracking on Android;
- forced GPS recovery when the location stream goes stale;
- encrypted local location queue + original-timestamp replay after reconnect;
- consent-based Trusted Circle;
- Sent / Delivered / Acknowledged states;
- responder Emergency Inbox;
- ViraNari in-app Live Track with route trail, speed, direction, battery and last-known location;
- external **Open map** for the latest coordinates;
- emergency History;
- Practice Mode;
- false-alarm cancellation and “I'm safe” resolution.

## Backend quick start

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

Expected version: `1.5.0`.

## Add real Safe Nodes

List:

```bash
cd backend
source venv/bin/activate
python manage_safe_nodes.py list
```

Add a place after manually verifying the real location/coordinates:

```bash
python manage_safe_nodes.py add \
  --name "Campus Security Gate" \
  --category campus_security \
  --lat YOUR_REAL_LATITUDE \
  --lon YOUR_REAL_LONGITUDE \
  --address "Actual checked address" \
  --verified
```

Do not mark demo/guessed coordinates as verified for real-world use.

## Mobile preparation on Arch

```fish
./scripts/prepare_mobile.fish
cd mobile
flutter clean
flutter pub get
flutter analyze
```

Run against your VPS:

```fish
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR_API_DOMAIN
```

`flutter_compass` is added in V1.5, so perform a full rebuild rather than hot-reloading from V1.4.x.

## Safety Map two-phone test

1. Sign into ViraNari on Phone A and Phone B.
2. Open **Safety Map** on both phones.
3. Turn anonymous presence ON on both.
4. Wait around 10–20 seconds.
5. Each phone should see the other as an anonymous pink dot if inside the selected radius.
6. The dot deliberately does not correspond to the other phone's exact GPS point.

## Silent SOS test

1. Ensure a Trusted Circle recipient exists.
2. Long-press the shield beside **ViraNari** in the app bar.
3. Sender receives two haptic pulses.
4. Receiver opens Inbox and should see **SILENT SOS**.
5. Receiver can open Live Track/Open Map normally.
6. Hold the shield again (or hold the normal SOS control) on the sender to reveal the emergency controls.

## Important prototype boundary

ViraNari V1.5 is a hackathon/prototype safety system, not a certified emergency-dispatch product. Safe Nodes must be verified by humans, platform background behavior must be tested on each target phone, and the server should use HTTPS, production database migrations, monitoring and backups before real deployment.
