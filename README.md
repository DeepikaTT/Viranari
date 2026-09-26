# ViraNari V1.8.4 — Emergency Active Live Coordination

V1.8.4 keeps the rich V1.8.3 Safety Map and restores the large **Emergency ACTIVE** card on Home so the victim can immediately see emergency state, acknowledgement, both users, live movement trails, distance and ETA without opening another screen.

## Emergency ACTIVE card
During an active SOS, Home now shows:
- `Emergency ACTIVE` plus Sent/Delivered/Acknowledged state;
- acknowledged/delivered counts;
- embedded map;
- victim marker and latest victim trail;
- nearest acknowledged responder marker and responder breadcrumb trail;
- live distance and approximate ETA;
- victim and responder GPS coordinates plus responder update time;
- recenter control;
- `I'm safe` and `False alarm` actions.

Responder movement uses stored GPS breadcrumbs. The card intentionally does not invent a straight road route between users.

## Existing core retained
- Silent logo-hold SOS;
- continuous emergency GPS and independent heartbeat;
- offline GPS queue and reconnect replay;
- Live Track + live GPS updates feed;
- rich Safety Map and Safety Compass;
- Trusted Circle, Inbox, History and acknowledgement;
- Android notification-bar SOS alert and in-app emergency alert.

## Validate

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
```

Expected backend tests: `37 passed`.
