# ViraNari V1.5.0 — Judge / PPT Features

## Core retained
- V1.4.4 V2-style interface.
- Press-and-hold SOS.
- Trusted Circle consent + acknowledgement.
- Continuous ~5-second emergency location tracking.
- Heartbeat-based LIVE / DELAYED / OFFLINE state.
- Offline GPS queue + reconnect replay.
- Full live location timeline with timestamp, coordinates, accuracy, battery, network and speed.
- Direct Open Map action.

## SafeReach — verified responder network
- Matches only administrator-verified responders.
- Availability + recent-presence + service-radius checks.
- Nearest eligible responder selection.
- Responder lifecycle: OFFERED → ACCEPTED → ARRIVED → COMPLETED.
- Unanswered offers expire and automatically escalate to the next eligible verified responder.
- Traveler and Trusted Circle see responder status.
- No public nearby-user map and no random responder exposure.

## ProofChain — cryptographically verifiable emergency actions
- SHA-256 hash-linked event chain.
- Ed25519 signatures using a persistent backend key.
- Public verification key endpoint.
- Verify Integrity endpoint detects altered events.
- Key actions such as SOS creation, responder routing, acknowledgement, location replay and resolution are signed.
- Correct claim: tamper-evident, not magically tamper-proof.

## Emergency communication
- Call Trusted Circle from active SOS.
- Call emergency services from active SOS.
- Trusted Contact can call sender from Inbox.
- Matched responder can be called when a phone number is available.
- SMS remains intentionally placeholder-only for a future transport layer.

## Demo differentiator
SOS → Trusted Circle notified → SafeReach verified responder matched → responder accepts → live location timeline continues → ProofChain verifies all incident actions.
