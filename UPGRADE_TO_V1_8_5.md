# Upgrade to ViraNari V1.8.5

V1.8.5 has no database migration. It updates the Home emergency UI and the Android notification bridge for nearby arrival alerts.

## Apply the sync patch

```fish
cd ~/Downloads/viranari_v1_8_5_sync_patch
./apply_sync_v1_8_5.fish ~/Projects/Viranari
```

The patch makes a timestamped backup before replacing files. If an Android wrapper already exists, the apply script also reruns `scripts/patch_mobile.py` so the new proximity notification method is available.

## Validate mobile

```fish
cd ~/Projects/Viranari/mobile
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
```

A full APK rebuild/install is required because native Android notification code changed.

## Backend

Restart the backend after deploying the version bump and check:

```bash
curl http://127.0.0.1:3000/health
```

Expected API version: `1.8.5`.
