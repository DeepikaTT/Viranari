# ViraNari V1.5.0 Product Design Spec

## Product principle
Emergency response should fail gracefully, disclose freshness honestly and never expose a distressed user to unverified nearby strangers.

## Locked V1.4.4 UX
- Bottom navigation: Home / Circle / Inbox / History.
- Large hold-for-help SOS.
- Rich emergency cards, visible coordinates, external Open Map.
- Full location timeline rather than a dedicated always-on map tab.

## SafeReach
- Automatic nearest eligible verified-responder routing on SOS.
- Responder identity shown as organization + responder name + category + approximate match distance.
- States: REQUEST SENT → RESPONDER COMING → RESPONDER ARRIVED → COMPLETED.
- User-controlled rematch while an offered responder has not accepted.

## ProofChain
- Integrity card should be understandable first: Verified / Needs attention.
- Technical detail remains inspectable: event count, SHA-256 chain state, Ed25519 signature state, public key ID and recent signed actions.

## Calls
- Calls always go through the system phone UI; ViraNari does not silently place phone calls.
- Active SOS surfaces Trusted Circle, emergency-service and matched-responder call actions.

## Privacy
- No public nearby-user radar.
- Only the assigned verified responder receives the incident location through responder-authorized APIs.
- Trusted Contact phone numbers remain consent-based as in V1.4.4.
