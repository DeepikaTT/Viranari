# ViraNari V1.5.0 Customer Acceptance Checklist

Use physical phones for acceptance testing.

- [ ] Existing V1.4.4 account can log in after backend upgrade.
- [ ] Existing Trusted Circle remains present.
- [ ] Existing History remains readable.
- [ ] Hold SOS creates an active emergency.
- [ ] Sender location changes while walking/driving outdoors.
- [ ] Receiver Inbox refreshes latest coordinates.
- [ ] Location timeline shows every stored record, not only the latest one.
- [ ] Screen-lock/background test continues tracking on supported Android settings.
- [ ] Wi-Fi → mobile-data transition recovers without ending SOS.
- [ ] Temporary internet loss queues/replays location records.
- [ ] Trusted Contact acknowledgement reaches sender.
- [ ] Call Trusted opens the system dialer with the accepted contact number.
- [ ] Call Emergency opens the configured emergency number.
- [ ] Verified responder is matched only when available, recent and within radius.
- [ ] Unverified account cannot open responder APIs.
- [ ] Responder can accept → arrive → complete.
- [ ] Unanswered responder offer expires and the next eligible responder is tried automatically.
- [ ] Traveler/Trusted Contact sees responder status.
- [ ] ProofChain Verify reports valid on an untouched incident.
- [ ] Backend tamper test causes ProofChain verification failure.
- [ ] Test Drill remains clearly labelled as TEST.
- [ ] SMS permission is NOT requested in V1.5.0.
