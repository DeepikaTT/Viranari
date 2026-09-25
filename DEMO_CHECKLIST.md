# ViraNari V1.4 Demo Checklist

## Before judges arrive

- [ ] HTTPS backend reachable
- [ ] `/health` returns 1.4.0
- [ ] two Android accounts prepared
- [ ] Trusted Circle accepted
- [ ] phone numbers in E.164 format
- [ ] sender GPS permission granted
- [ ] background location allowed where possible
- [ ] SMS fallback prepared on physical Android phone
- [ ] real TEST SMS verified on team devices
- [ ] Practice Mode OFF for transport test; ON for safe stage demos

## 90-second demo

1. Show the clean Home screen: status strip + SOS, no feature-card wall.
2. Start Journey Guard for “Hostel — 30 min”.
3. Press-and-hold SOS on sender.
4. Responder opens Response → Track.
5. Show LIVE based on **device heartbeat**, plus separate GPS age.
6. Keep sender stationary: LIVE should remain LIVE.
7. Move sender/emulator GPS: marker, trail, direction and distance travelled change.
8. Disable sender data: responder transitions to DELAYED/OFFLINE but retains marker.
9. Sender continues collecting GPS locally; SMS fallback may fire once.
10. Restore data: heartbeat and queued trail reconcile; responder returns to LIVE.
11. Open Nearby to show anonymous Safety Presence radar.

## Never claim as implemented

- BLE/multi-hop ViraMesh
- police dispatch integration
- certified emergency response
- push notifications while the recipient app is completely inactive
- offline map tiles
- verified Safe Node partnership network
