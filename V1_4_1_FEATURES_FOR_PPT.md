# ViraNari V1.4.1 — PPT feature sheet

## Current prototype

- Press-and-hold emergency SOS
- Real GPS location and active emergency sessions
- Dedicated Live Map tab
- Find-My-style moving marker and route trail
- Device heartbeat separate from GPS freshness
- Fast emergency GPS refresh with zero distance filter
- Last-known location retained through disconnection
- Offline GPS queue and reconnect replay
- Trusted Circle consent and acknowledgements
- SMS fallback with explicit Android permission/SIM diagnostics
- Phone-number cache for accepted Trusted Circle contacts
- Anonymous Safety Presence radar
- Device-based nearby presence, including separate phones on the same test account
- Battery, network, accuracy, direction and distance-travelled status
- Practice Mode
- Persistent FastAPI backend

## Removed from this milestone

Journey Guard was intentionally removed so the demo stays focused on immediate emergency response, live map tracking, SMS fallback and nearby safety presence.

## Demo message

> One SOS starts an emergency session, keeps the victim visible on a live map, retains the last-known trail if connectivity drops, falls back to SMS when possible, and shows whether anonymous ViraNari devices are physically nearby.
