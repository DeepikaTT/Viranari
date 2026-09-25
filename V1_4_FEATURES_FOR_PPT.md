# ViraNari V1.4 — PPT Feature Sheet

## Six feature pillars

### 1. Reliable SOS
- Press-and-hold activation
- real GPS
- consent-based Trusted Circle
- SENT / DELIVERED / ACKNOWLEDGED states
- offline SOS retry and idempotency
- resolve-safe / false-alarm states

### 2. Find-My-style Live Safety
- live movement trail
- heartbeat-based LIVE / DELAYED / OFFLINE
- GPS freshness shown separately
- last known location retained after disconnect
- background emergency location configuration
- forced GPS refresh and stream restart
- queued offline GPS replay with original timestamps
- battery, network, speed, direction, accuracy and distance travelled

### 3. Connectivity Survival
- API first
- local encrypted GPS queue during outage
- SMS fallback on sustained outage
- one successful fallback SMS per outage
- SIM/default-subscription diagnostics
- real TEST SMS transport check
- immediate recovery/reconciliation when internet returns

### 4. Journey Guard
- destination + expected arrival
- Trusted Circle can monitor the active journey
- server-side overdue detection
- user can mark journey safe

### 5. Safety Presence
- anonymous nearby-device radar
- opt-in only
- short-lived presence
- no public names, phone numbers, account IDs or exact coordinates
- approximate distance + direction only

### 6. Victim-first UI
- one dominant SOS action
- minimal Home surface
- compact health strip
- secondary controls hidden until needed
- map-first responder experience
- clear separation between phone liveness and GPS freshness

## Technical stack

**Mobile:** Flutter / Dart, Geolocator, secure storage, Connectivity Plus, Flutter Map, native Android SMS bridge.

**Backend:** FastAPI, SQLAlchemy, SQLite prototype database, JWT, Argon2, rate limiting, audit trail, compatibility migrations.

## Key design sentence

> One action from the victim. Multiple automatic paths to human help.

## Roadmap after V1.4

- Verified Safe Nodes
- Safety Compass / offline map package
- Silent/stealth activation research
- Firebase/APNs push
- V2 ViraMesh BLE relay
