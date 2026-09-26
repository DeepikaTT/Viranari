# ViraNari V1.5 Design Spec

## Keep the V1.4.3 core UI
Bottom navigation remains:
**Home · Circle · Inbox · History**

Do not turn every feature into a permanent navigation tab.

## Home additions
Two compact actions near the existing status area:
- **Safety Map**
- **Compass**

The existing SOS, location coordinates, Open Map action and emergency status remain unchanged.

## Silent trigger
The shield icon beside `ViraNari` is a hidden-but-learnable emergency affordance:
- long press → Silent Safety Session;
- two haptic pulses;
- no loud sound;
- no immediate red emergency takeover;
- hold again or hold normal SOS to reveal controls.

## Safety Map visual language
- Dark/plum current-user marker.
- Pink anonymous presence dots.
- Teal/plum shield markers for verified Safe Nodes.
- No avatars, names, labels or exact location callouts for anonymous users.
- Map is the visual surface; avoid card-heavy dashboards over it.

## Safety Compass
Large directional arrow and distance are primary. The map is secondary.

## Privacy invariants
- Exact victim/SOS location is shared only through the existing Trusted Circle emergency flow.
- Safety Map anonymous presence is coarsened and short-lived.
- Nearby API does not return identity or exact peer coordinates.
- Safe Nodes are public physical locations and may use exact coordinates only after human verification.
