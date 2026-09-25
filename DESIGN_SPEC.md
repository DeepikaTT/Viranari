# ViraNari v0.1 UI Design Spec

The prototype intentionally uses a calm safety palette rather than making the entire app emergency-red.

- Background: `#FFF9FC`
- Plum primary/text: `#40223D`
- Muted plum: `#76506F`
- Lilac panel: `#F0E2F1`
- Strong lilac: `#D8BDDD`
- SOS pink: `#E94378`
- SOS dark: `#C9275E`
- Confirmed/acknowledged green: `#267A5A`
- Success background: `#E4F4EC`

Interaction principles:

- The SOS control dominates the Home screen.
- SOS requires a long press and produces haptic confirmation.
- Emergency status uses explicit text: Sent → Delivered → Acknowledged.
- Green is reserved for server-confirmed success states.
- The app never equates “request submitted” with “help notified.”
- Trusted-contact enrollment is consent-based rather than silently adding a phone/email.
- Large controls and readable status labels support stressful, low-attention usage.
