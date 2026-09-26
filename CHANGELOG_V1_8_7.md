# ViraNari V1.8.7 — Clean Emergency Actions + India 112

V1.8.7 is a focused Home-screen cleanup on top of V1.8.6.

## Changes

- Removed the diagnostic Home card that showed server sync time, queued GPS count, GPS accuracy and current-coordinate debug text.
- Kept a single clean **Open map** action.
- Added a prominent **Call 112 — India Emergency** action. It opens the device telephone handler with India's national ERSS emergency number 112.
- Bundled the user-provided `app_icon.png` unchanged at `mobile/assets/icon/app_icon.png`.
- Added `flutter_launcher_icons` configuration so `prepare_mobile.fish` automatically generates Android/iOS launcher icons from that same file.
- Retains all V1.8.6 Emergency Active, responder tracking, proximity notification, Safety Map and Safety Compass functionality.
- Fixed the V1.8.6 apostrophe compile typo in the Live Track ETA helper text.

Mobile version: `1.8.7+47`  
Backend API version: `1.8.7`
