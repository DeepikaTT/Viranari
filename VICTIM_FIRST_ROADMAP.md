# ViraNari — victim-first roadmap after v1.2

## Design principle

A person in immediate danger may be running, hiding, injured, shaking, unable to type, unable to speak, unable to safely look at the screen, or have only seconds before the phone is taken. Features must therefore minimize interaction rather than add dashboards.

## Highest-value next concepts

### 1. Safety Presence — nearby ViraNari devices without creating a stalking map
Do **not** show precise live locations of ordinary users as public dots. That can become a tool for stalking.

Safer design:
- opt-in presence only
- rotating anonymous device IDs
- approximate/coarse positions or density bubbles
- short expiry (for example 30–60 seconds)
- display `3 ViraNari devices nearby` rather than identities
- reveal exact location only after an emergency request and explicit responder acceptance
- BLE presence can work as relay discovery even when internet is unavailable

Victim UI example:

`Nearby safety network: 4 devices · nearest relay ~80 m`

### 2. Escalation ladder
One SOS should fan out in layers instead of requiring the victim to choose who to contact:
1. Trusted Circle
2. Nearby opted-in ViraNari responders
3. Verified Safety Nodes (campus security, pharmacy, shop, hostel desk, hospital)
4. Official emergency channel/integration where technically and legally available

### 3. Journey Guard
Before a risky trip, the user taps one button:
- destination + expected arrival time
- passive route progress
- missed-arrival check-in
- route deviation / prolonged stop prompt
- if the user fails a short safety check, escalate to trusted circle

This must be opt-in; it should not continuously track users by default.

### 4. Silent / one-hand triggers
Potential Android implementation:
- hardware-button sequence where OS rules allow it
- lock-screen shortcut
- silent haptic confirmation
- optional code phrase
- discreet screen state after activation

The activation path should work without typing or navigating menus.

### 5. Verified Safe Nodes
Partner with real-world places that are open and staffed:
- pharmacies
- hospitals
- college security desks
- hostel desks
- selected shops/cafes
- transport help desks

A node gets a verified badge, staff protocol, and a visible sticker/QR. The app can guide the victim toward a staffed place instead of only displaying a police station on a map.

### 6. Bystander/Responder mode
A nearby responder should not be told to physically confront an attacker. The app should guide safer actions:
- acknowledge the alert
- call security/emergency services
- approach with other people if safe
- move toward a public staffed location
- observe/share useful information without escalating danger

### 7. Campus / institution safety layer
For colleges, hostels and workplaces:
- verified security control room
- hostel warden / designated safeguarding officer
- safe-gate check-in
- campus escort request
- anonymized hotspot reporting for administrators
- emergency alerts to the closest staffed security node

### 8. Evidence Capsule (opt-in)
After SOS, optionally preserve an encrypted evidence package such as timestamps, GPS trail, user-entered note and selected media. Audio/video recording rules vary by context and jurisdiction, so this should be explicit and user-controlled rather than permanent covert surveillance.

### 9. Offline ViraMesh
The flagship resilience feature:

`Victim phone → nearby ViraNari phone → relay → internet-capable gateway → backend/trusted circle`

Start with two physical Android phones before attempting true multi-hop routing.

### 10. Safety Compass + offline map
When the victim cannot focus on a full map, display one large arrow to a verified safe destination using cached coordinates + GPS + magnetometer. Do not ask an LLM to invent emergency locations.

## Proposed next milestone

**v1.3: Safety Presence + Journey Guard + silent trigger prototype**, then **v2: two-phone ViraMesh relay**.
