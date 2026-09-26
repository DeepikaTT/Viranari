# ViraNari V1.8.3 — Rich Safety Map + Live GPS + SOS Notifications

V1.8.3 keeps the V1.8.2 live GPS feed and Android SOS notification-bar alert, and fixes the Safety Map so anonymous people radius controls do not hide hospitals, police stations, pharmacies or other safety places.

## What changed in V1.8.3

### 1. Safety places no longer follow the 500 m / 2 km / 5 km people filter
The segmented control now means exactly **Anonymous people radius**. It changes only:
- the backend anonymous-presence query;
- which anonymous ViraNari dots are returned.

It does **not** remove safety-place pins.

### 2. Rich safety-place map
The Safety Map now discovers and renders safety places out to **15 km**:
- hospitals and clinics;
- police stations;
- pharmacies;
- fire stations / staffed help locations;
- ViraNari verified Safe Nodes.

Verified nodes are still preferred when a public OpenStreetMap result refers to effectively the same place. Public places remain clearly marked as public/not ViraNari verified.

### 3. Show-all-safety-places control
The map automatically fits the discovered safety places on first load. A new **Show all safety places** map button can fit them again after the user pans or zooms. The normal **My location** button returns to the user's location.

### 4. Existing V1.8.2 features remain
- live victim/responder GPS tracking;
- live GPS update feed;
- responder trail;
- victim ↔ responder distance and approximate ETA;
- incoming SOS full-screen in-app alert;
- persistent Android notification-bar SOS alert while the app process can poll;
- Silent SOS, Trusted Circle, Inbox, History, Safety Compass, Open Map and offline GPS queue.

## Version
Mobile: `1.8.3+43`  
Backend health/API version: `1.8.3`

## Validate locally

```fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
```

Backend:

```bash
cd backend
python -m pytest -q
python run.py
```

Health:

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.8.3`.
