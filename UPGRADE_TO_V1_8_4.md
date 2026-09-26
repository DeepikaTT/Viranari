# Upgrade to ViraNari V1.8.4

V1.8.4 is primarily a mobile Home-screen coordination restore. No database migration is required.

## Mobile

```fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
```

The Emergency ACTIVE card now loads the alert owner GPS trail plus the current acknowledged responder and responder breadcrumb trail from the existing V1.8 APIs.

## Backend
The data model/API schema is unchanged; only the release version string is bumped. Keep your existing `.env`, database and virtual environment, restart the backend, then verify:

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.8.4`.
