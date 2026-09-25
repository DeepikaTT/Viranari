# ViraNari v1.3 design system

Victim-first rule: an emergency flow must remain usable one-handed, under stress, with minimal reading and no transport/network choices forced on the victim.

Brand palette:
- Deep Teal `#073F42`
- Midnight Teal `#052E31`
- Lotus Pink `#D95D83`
- Emergency Red `#D93645`
- Antique Gold `#C9963B`
- Warm Ivory `#FFF9F0`
- Success Green `#23845D`

Emergency hierarchy:
1. SOS / active emergency state
2. Last known victim position and freshness (LIVE / DELAYED / LAST SEEN)
3. Delivery + human acknowledgement
4. Phone GPS fix vs server-sync health
5. Battery/network/SMS fallback state
6. Secondary settings/history

Safety rules:
- Never remove a victim marker because connectivity disappeared; preserve the last known position.
- Never label an SMS as delivered when the app only knows it was dispatched.
- Never expose a Trusted Circle phone number before consent.
- Never make the victim choose Internet vs SMS; fallback is automatic after preparation.
- Never delay SOS transmission with a decorative countdown.
