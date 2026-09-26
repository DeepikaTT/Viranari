# Upgrade to ViraNari V1.8.6

No database migration is required.

## Mobile

Replace/update the V1.8.5 mobile source and run:

```fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
```

Because responder tracking uses the existing native foreground-location capability, a normal full APK rebuild/install is recommended rather than relying on hot reload.

## Backend

The backend data model is unchanged. Update the backend source, keep `.env` and your database, then restart the service.

Expected health version: `1.8.6`.

## Two-phone test

1. Victim starts SOS.
2. Responder accepts and opens Live Track.
3. Verify ETA + distance are visible on responder Live Track.
4. Verify the same ETA + distance appear on victim Home > Emergency Active.
5. Move responder; both displays should update every few seconds.
6. Briefly block GPS / lock-unlock responder phone; last reliable position should remain instead of immediately showing a timeout.
7. Open Safety Map and switch 500 m -> 2 km -> 5 km; zoom and anonymous-device query should visibly change each time.
