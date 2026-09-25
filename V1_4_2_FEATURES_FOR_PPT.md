# ViraNari V1.4.2 — PPT feature sheet

## Current implemented prototype

- Press-and-hold SOS
- Real GPS emergency location
- Find-My-style live map
- Moving location marker and route trail
- Device heartbeat separate from GPS movement
- LIVE / DELAYED / OFFLINE liveness state
- Last-known location retained after disconnect
- Continuous emergency GPS tracking (`distanceFilter: 0`)
- Forced GPS refresh if the normal stream goes quiet
- Background Android emergency-location service
- Speed, direction, travelled distance and accuracy
- Offline encrypted GPS queue
- Automatic reconnect and queued-location replay
- Consent-based Trusted Circle
- Multi-recipient SOS delivery
- Sent / Delivered / Acknowledged states
- Trusted-contact response acknowledgement
- Emergency Inbox
- Emergency history
- Battery/network status
- Practice mode
- False-alarm cancellation
- "I'm safe" emergency resolution
- FastAPI backend + persistent database
- Authentication, rate limiting, audit events and idempotent SOS creation

## Intentionally removed from this build

Journey Guard, Safety Presence/Nearby radar and SMS fallback are not part of V1.4.2. The team is prioritising a smaller emergency core that can be demonstrated reliably end-to-end.

## One-line positioning

> ViraNari keeps a trusted person connected to a victim's last reliable and current live location throughout an emergency, including temporary network loss and recovery.
