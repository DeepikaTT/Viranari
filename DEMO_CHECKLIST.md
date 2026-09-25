# ViraNari v0.1 Judge Demo Checklist

## Before the demo

- Backend `/health` returns `status: ok`.
- Both phones can reach the backend.
- Location permission granted on the SOS phone.
- Two separate accounts created.
- Trusted-contact invitation accepted.
- Home screen shows queue clear.

## Live demo

1. Show Trusted Circle consent status = ACTIVE.
2. Press and hold SOS on Phone A.
3. Show the real GPS coordinate captured.
4. Point out status is only SENT.
5. Open/refresh Emergency Inbox on Phone B.
6. Refresh Phone A and show DELIVERED.
7. Tap acknowledgement on Phone B.
8. Refresh Phone A and show ACKNOWLEDGED.
9. Open History and show the persistent event.

## Offline resilience demo

- Stop backend / disconnect A.
- Trigger SOS after GPS capture.
- Show secure queued status.
- Restore connectivity.
- Refresh Home.
- Show queue reconciled without duplicate event.

## Do not claim yet

- Do not call v0.1 a multi-hop mesh.
- Do not claim background push notifications.
- Do not claim police dispatch integration.
- Do not claim the emulator proves BLE; test BLE on two physical phones in v0.2.
