# ViraNari v1.3 — PPT feature summary

## Core message
**V1.3 turns an SOS into a resilient live safety session: track the victim like Find My, preserve the last known position, and fall back to SMS when internet/API delivery fails.**

## Implemented
- Press-and-hold emergency SOS
- Real GPS + active emergency session
- Find-My-style live map for Trusted Circle
- Continuously refreshed current marker
- Movement trail / route history
- LIVE / DELAYED / LAST SEEN states
- Last-known location retained after disconnect
- Device disconnect warning
- Phone GPS fix vs server-sync timestamps
- Correct UTC → device-local time display
- Battery/network/accuracy indicators
- Speed + direction when available
- Background Android foreground tracking configuration
- Secure offline location queue + automatic replay
- Consent-based Trusted Circle
- Trusted contact phone numbers only after consent
- Encrypted local trusted-phone cache
- SMS fallback if API/internet fails
- Android direct SMS after pre-granted permission
- iOS user-approved Messages composer fallback
- Call victim from trusted-contact alert
- Sent / Delivered / Acknowledged states
- Practice mode
- False-alarm cancel + I'm Safe resolution
- Backward-compatible SQLite schema upgrade
- 22 backend automated tests

## Not claimed as implemented yet
- BLE / multi-hop ViraMesh
- background push notification delivery
- offline map tiles
- emergency-service/police API integration
- Safety Presence nearby anonymous dots
- Journey Guard
- Silent hardware SOS
