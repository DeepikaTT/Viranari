# Upgrade to ViraNari V1.8.3

V1.8.3 is primarily a Safety Map behavior fix. No database migration is required.

## Mobile
Replace the V1.8.2 mobile source with V1.8.3, then:

```fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
```

Because V1.8.2 already added the Android notification bridge, no new native notification permission is introduced by this release.

## Backend
The API schema is unchanged; the release version string is bumped to 1.8.3. Keep `.env`, the existing database and virtual environment. Restart the service and verify:

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.8.3`.
