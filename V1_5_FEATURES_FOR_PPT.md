# ViraNari V1.5 — PPT Feature Sheet

## Core idea
**ViraNari builds a live safety layer around the user.**

### 1. Safety Map — “Who is around me?”
- Full-screen map with anonymous nearby ViraNari presence as dots.
- User's own position is shown normally.
- Nearby people are deliberately approximate, not exact.
- Mutual opt-in: a phone must share anonymous presence to view other presence.
- Short-lived presence automatically disappears when a device stops broadcasting.
- No names, phone numbers, account IDs, device IDs, or exact nearby-user coordinates are exposed.
- Verified Safe Nodes appear as shield markers.

### 2. Silent Safety Session — “Ask for help without visibly asking.”
- Long-press the ViraNari shield/logo.
- Two haptic pulses confirm activation.
- Trusted Circle notification + live GPS + heartbeat start in the background.
- Sender UI suppresses obvious emergency styling until intentionally revealed.
- Responder sees **SILENT SOS** and is warned the victim may be unable to interact safely.

### 3. Safety Compass — “Get me toward human help.”
- Points toward the nearest selected verified Safe Node.
- Uses GPS + phone compass + bearing calculation.
- Shows distance and direction.
- Previously fetched Safe Nodes are cached for network-loss use.
- Safe Nodes must be manually verified; AI never invents emergency locations.

## Emergency core retained
- Press-and-hold SOS.
- Find-My-style live location session.
- LIVE / DELAYED / OFFLINE heartbeat state.
- GPS route trail, speed, direction and distance travelled.
- Offline GPS queue and reconnect replay.
- Trusted Circle consent.
- Sent → Delivered → Acknowledged.
- Open latest coordinates in Maps.
- In-app Live Track.
- Last-known position after disconnect.
- Emergency Inbox + History.

## Pitch line
**See help. Reach help. Signal help — even when you cannot safely speak.**

## Next major R&D milestone
**ViraRelay / ViraMesh:** encrypted nearby-phone SOS relay when normal internet connectivity fails.
