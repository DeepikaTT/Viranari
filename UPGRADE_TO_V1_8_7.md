# Upgrade to ViraNari V1.8.7

## Mobile

Apply the sync patch, then run:

```fish
cd ~/Projects/Viranari/mobile
flutter clean
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter build apk --release
```

The icon source is already bundled as `assets/icon/app_icon.png`; you do not need to prepare or upload it again.

## Emergency calling

The Home screen now includes **Call 112 — India Emergency**. The app hands `tel:112` to Android/iOS so the system telephone app handles the emergency call. No `CALL_PHONE` permission is required.

## Backend

No schema migration is required. Deploying the V1.8.7 backend only updates the reported API version.
