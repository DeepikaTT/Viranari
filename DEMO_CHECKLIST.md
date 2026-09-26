# ViraNari V1.5.0 Demo Checklist

## Before judges arrive
- Backend `/health` reports `1.5.0`.
- Traveler, Trusted Contact and Responder accounts can log in.
- Responder account is admin-verified.
- Responder console shows VERIFIED and availability ON.
- Responder location has been refreshed recently.
- Traveler and Trusted Contact have accepted Trusted Circle relationship.
- Both phones have precise/background location permissions and sensible battery settings.

## Demo
1. Traveler holds SOS.
2. Home shows emergency active and V1.4.4 tracking continues.
3. Trusted Contact sees the emergency in Inbox.
4. Open Location Timeline: multiple records appear newest-first and keep refreshing.
5. Open SafeReach: nearest verified help is shown.
6. Responder Console receives the assigned incident.
7. Responder taps Accept; traveler/contact SafeReach status changes to RESPONDER COMING.
8. Responder taps Mark arrived; status changes to RESPONDER ARRIVED.
9. Open ProofChain: integrity should show verified with Ed25519 signatures + SHA-256 chain.
10. Demonstrate Call Trusted / Call Sender / Call Responder actions using system dialer.
11. Mark traveler safe to close the incident.

## Do not claim
- Do not call the log physically "tamper-proof". Say **tamper-evident and cryptographically verifiable**.
- Do not claim SafeReach can reach random nearby people. Only verified/available/recent responders are eligible.
- Do not claim SMS is implemented in V1.5.0. It remains a placeholder.
