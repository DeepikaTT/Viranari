# ViraNari V1.8.2 — Safety Map Density + Live GPS Feed + SOS Notifications

## Fixes
- Safety Map no longer stops at a single operator-verified Safe Node.
- Verified Safe Nodes are merged with public OpenStreetMap hospitals, clinics, police stations, pharmacies and fire stations.
- Public discovery uses per-category caps so hospitals/police are not crowded out by dense pharmacy data.
- Public healthcare tags are included in addition to amenity tags.
- 500 m / 2 km / 5 km filtering still controls which markers are visible.

## Live GPS feed
- Live Track now shows a changing `LIVE GPS UPDATES` timeline.
- Shows the latest four GPS samples, timestamp, coordinates, accuracy and movement delta.
- This is a location-update timeline only; it is not an emergency-event timeline.

## Android SOS notification bar
- Incoming unacknowledged SOS can create a persistent high-priority Android notification.
- Tapping the notification opens ViraNari; the existing full-screen SOS overlay remains in-app.
- Notification is cleared when the SOS is acknowledged or no longer pending.
- Android 13+ notification permission is requested.
- Sender-side foreground location notification now reads `ViraNari SOS ACTIVE` while live tracking is running.

## Important limitation
Local notification delivery depends on the ViraNari app process being alive enough to poll the inbox. Reliable delivery after the app is force-stopped/killed requires push infrastructure such as FCM/APNs.

Version: `1.8.2+42`.
