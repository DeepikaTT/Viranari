# ViraNari V1.6.0 Product Design Spec

## Product priority
The emergency path is ordered by immediate user value:

1. Start SOS without typing.
2. Keep recording location locally regardless of internet state.
3. Notify and track through Trusted Circle when data is available.
4. Offer direct phone-call actions using consented phone numbers.
5. Offer SMS fallback when mobile data is unavailable but cellular SMS exists.
6. Offer Verified Help only where an approved responder network exists.
7. Preserve a human-readable, cryptographically verifiable incident record after and during the emergency.

## UX rules
- Do not hide last-known location when connectivity is lost.
- Distinguish device liveness, GPS freshness and server synchronization.
- Never call a prepared SMS "sent" or a dialer-open event "connected".
- Verified Help is optional infrastructure, not a prerequisite for SOS.
- Cryptographic details are secondary to a readable incident timeline.
- Existing V1.4.4 location timeline and external Open Map flow stay intact.
