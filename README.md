# ViraNari V1.8.5 — Clean Emergency Active

V1.8.5 keeps the V1.8.4 emergency coordination system but cleans the Home UI and makes proximity between the victim and acknowledged responder easier to understand.

## Main changes

- Cleaner Emergency ACTIVE card.
- One live separation line on the Home emergency map instead of multiple overlapping trails.
- Fresh client-side GPS distance using the latest victim/responder coordinates.
- Combined GPS accuracy shown beside the live separation measurement.
- Nearby alert at <=100 m for both victim and responder.
- Android notification-bar proximity alert with 150 m reset hysteresis.
- Cleaner compact Home GPS/status card.

The dedicated Live Track screen still retains the full victim/responder breadcrumb history and live GPS updates timeline.

## Validation

Backend tests: `37 passed`.

Flutter is not installed in the packaging environment, so run `flutter analyze` locally before building the APK.
