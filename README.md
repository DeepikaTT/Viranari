# ViraNari V1.4.1 — Live Map Reliability Hotfix

V1.4.1 is a focused correction release based on real-device testing. It removes Journey Guard from the product, restores the map as a first-class navigation tab, makes emergency GPS refresh much more aggressive, adds useful SMS permission/SIM diagnostics, and changes Safety Presence from account-based to device-based presence.

## What changed from V1.4

### 1. Journey Guard removed
Journey Guard is removed from the Flutter UI, responder polling, mobile API client, FastAPI routes, and fresh database model. Existing VPS databases are not destructively altered; an old `journeys` table may remain unused after upgrading.

### 2. Map is a core tab again
The bottom navigation is now:

- Home
- Map
- Circle
- Response

The Map tab always exists. During an active SOS it follows the live emergency marker and trail. A trusted contact automatically sees the newest active emergency they are responding to. With no active emergency it shows the current phone position when permission is available.

The dedicated responder Live Safety map remains available from Response -> Track.

### 3. Faster Find-My-style location updates
During an active SOS:

- Android location stream requests `bestForNavigation`
- `distanceFilter = 0`
- requested stream interval = 5 seconds
- liveness heartbeat = 5 seconds
- if no fresh GPS fix is seen for ~8 seconds, the app requests an explicit current position
- responder maps refresh every 3 seconds
- GPS and server liveness remain separate

Android/iOS plugin settings are deliberately created without forcing `const`, avoiding the package-version compile issue seen in earlier builds.

### 4. SMS setup diagnostics and native permission request
V1.4.1 no longer collapses every SMS problem into "SMS fallback is not ready".

Diagnostics separately show:

- SEND_SMS declared in installed APK
- SMS runtime permission granted
- phone supports SMS telephony
- SIM/eSIM is ready
- default SMS subscription is selected

`Prepare SMS` now requests `SEND_SMS` through the Android activity itself. Buttons open App Settings and SIM/Wireless Settings for recovery.

**Important:** Android manifest and Kotlin changes require a full rebuild/reinstall. Hot reload cannot add a permission to an APK that is already installed.

### 5. Safety Presence dots fixed for multiple phones
V1.4 keyed anonymous presence by account user ID. That meant two phones signed into the same test account overwrote the same presence row and could never see one another.

V1.4.1 uses an encrypted-local installation UUID and a server-side `safety_presence_devices` table. The nearby API excludes only the requesting installation, not every phone signed into the same account.

The Presence screen also:

- republishes while open
- refreshes about every 6 seconds
- keeps data short-lived
- still returns only coarse distance/bearing/age
- never returns another device's account, phone number, device ID, or exact coordinates

## Backend

Python / FastAPI / SQLAlchemy / SQLite prototype backend.

Run:

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python run.py
```

Default:

```text
http://0.0.0.0:3000
```

Health:

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.4.1`.

## Flutter setup

On your Arch/fish machine:

```fish
cd viranari_v1_4_1
./scripts/prepare_mobile.fish
cd mobile
flutter clean
flutter pub get
flutter analyze
```

Local emulator backend:

```fish
flutter run --dart-define=VIRANARI_API_BASE=http://10.0.2.2:3000
```

VPS/HTTPS:

```fish
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR-API-DOMAIN
```

For SMS testing use a **physical Android phone with an SMS-capable SIM/eSIM**. After installing V1.4.1, open Safety controls -> SMS fallback -> Prepare SMS. Android should show the permission request if it is not already granted.

## Two-phone Safety Presence test

1. Install V1.4.1 on Phone A and Phone B.
2. Both may even use the same ViraNari account for testing.
3. On both phones open Nearby.
4. Enable "Broadcast this phone anonymously" on both.
5. Keep both within the selected radius.
6. Within the refresh window each device should show the other as an anonymous dot.

## Validation performed in this package

Backend: **31 automated tests pass**, including device-scoped Safety Presence.

The container used to generate this package does not have Flutter installed, so the Android build itself must be validated on the Arch Flutter environment with `flutter analyze` and `flutter run`.
