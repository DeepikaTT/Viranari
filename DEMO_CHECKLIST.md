# ViraNari V1.6.0 Demo Checklist

## Before demo
- Backend `/health` reports `1.6.0`.
- Traveler has a phone number configured in Circle.
- Trusted contact has accepted the Circle invitation and has a phone number configured.
- Open Circle once online so the accepted contact phone number is cached.
- Location permission: precise + background/all-the-time where available.
- Battery optimization disabled for the demo device.

## Core V1.4.4 regression
- Start SOS with hold gesture.
- Receiver sees Emergency Inbox.
- Move and verify coordinates change.
- Open the full live-location timeline and confirm multiple records are shown.
- Lock sender screen and verify tracking continues.

## Communication resilience
- Tap Call trusted and choose a contact if multiple are available.
- Disable mobile data while keeping cellular service on.
- Tap SMS fallback; Messages should open with GPS/time/accuracy/battery prefilled.
- While API is unavailable, confirm GPS journal queued count grows.
- Restore internet and verify queued location points replay into the timeline.

## Verified Help (optional demo)
- Use only if a real/demo verified responder profile has been configured.
- Responder accepts, marks arrived, and completes.
- Explain that this feature is optional and depends on an enrolled institution/responder network.

## Incident record
- History → Incident record.
- Show human-readable emergency actions.
- Show integrity verification as valid.
- Be precise: SMS event means the composer was prepared/opened, not that delivery was proven.
