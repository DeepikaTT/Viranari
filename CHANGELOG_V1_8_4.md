# ViraNari V1.8.4 — Emergency Active Home Map Restore

## Added
- Restored the large **Emergency ACTIVE** Home card used in earlier ViraNari flows.
- Embedded live OpenStreetMap directly inside the active emergency card.
- Victim marker and the nearest acknowledged responder marker are visible together.
- Victim GPS trail and responder GPS breadcrumb trail are rendered separately; no fake straight-line responder route is drawn.
- Live responder distance, approximate ETA, both GPS coordinates, responder update time and acknowledgement/delivery counts are shown in the Home card.
- A fit/recenter control keeps victim and responder visible as their positions change.
- "I'm safe" and "False alarm" remain directly available in the emergency card.

## Preserved from V1.8.3
- Rich Safety Map with public hospitals/clinics, police, pharmacies, fire stations and ViraNari Safe Nodes out to 15 km.
- 500 m / 2 km / 5 km applies only to anonymous ViraNari presence.
- Live GPS update timeline in Live Track.
- Responder breadcrumb trail, distance and approximate ETA.
- Android SOS notification-bar alert and in-app emergency takeover.
- Silent SOS, Safety Compass, Trusted Circle, offline GPS queue, Inbox and History.

Mobile version: `1.8.4+44`.
Backend API version: `1.8.4`.
