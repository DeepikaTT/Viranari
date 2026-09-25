# ViraNari v1.3 demo checklist

## Before demo
- [ ] Backend `/health` returns v1.3.0.
- [ ] Sender and responder accounts have E.164 phone numbers.
- [ ] Trusted Circle invitation accepted.
- [ ] Sender opened Circle once to cache trusted phone numbers.
- [ ] Android SMS permission prepared if demonstrating SMS fallback.
- [ ] Sender location permission granted.
- [ ] Responder has internet for the live map tiles.

## Demo A — live tracking
1. Sender holds SOS.
2. Sender Home shows phone GPS fix and server sync timestamps changing.
3. Responder opens Inbox → Live Track.
4. Change sender emulator GPS / physically move phone.
5. Marker moves and trail grows.
6. Responder acknowledges; sender sees acknowledgement count.

## Demo B — Last Seen
1. Keep SOS active.
2. Disconnect sender internet.
3. Sender continues GPS collection and queues points.
4. Responder retains the last known marker.
5. Freshness transitions LIVE → DELAYED → LAST SEEN.
6. Restore internet and confirm queued points sync.

## Demo C — SMS fallback (Android team devices only)
1. Ensure SMS fallback was prepared before starting.
2. Stop backend / disable mobile data while cellular SMS service remains available.
3. Trigger a non-Practice SOS on a controlled test phone.
4. SOS is queued locally and an SMS is dispatched to cached trusted numbers.
5. Restore internet and let the API queue reconcile.

Never demonstrate a real emergency message to an uninvolved person.
