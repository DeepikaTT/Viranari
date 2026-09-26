# ViraNari V1.8.5 — Clean Emergency Active

V1.8.5 is a focused UI and proximity upgrade on top of V1.8.4.

## Emergency Active card
- Rebuilt the Home emergency card to match the cleaner compact design.
- Status is shown as a pill; acknowledgement/delivery counts stay directly below the title.
- Home emergency map now draws exactly **one** blue live-separation line between the current responder and current victim positions.
- Historical breadcrumb trails remain available in the dedicated Live Track screen instead of cluttering the Home card.
- Distance on the Home card is recalculated locally from the latest victim and responder coordinates rather than only displaying the last server-rounded value.
- Shows combined GPS uncertainty when both devices report accuracy.

## Nearby arrival alert
- At 100 m or closer, the victim gets an in-app **Nearby alert** banner.
- Android notification-bar alert is generated for the victim when a responder first enters the nearby zone.
- The responder also receives an Android proximity notification when they get within 100 m of the victim while Live Track is sharing responder GPS.
- Hysteresis resets the alert only after devices separate beyond 150 m, preventing a notification every refresh.

## Cleaner Home GPS card
- Compact server-sync / queued-points / accuracy status on the left.
- Current GPS + Open map on the right.
- Background-location recommendation moved into a smaller information strip.

## Preserved from V1.8.4
- Rich Safety Map and independent safety-place radius.
- Safety Compass.
- Silent shield-hold SOS.
- Incoming SOS notification bar alert and full-screen in-app alert.
- Live GPS updates timeline.
- Offline GPS queue and reconnect replay.
- Trusted Circle, Inbox and History.

Mobile version: `1.8.5+45`.
Backend API version: `1.8.5`.
