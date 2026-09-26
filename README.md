# ViraNari V1.4.4 — V2 UI Restore + V1.4 Tracking Core

This release deliberately restores the V1.2 visual/interaction model while retaining the V1.4 tracking engine underneath.

## Locked product surface

- Home / Circle / Inbox / History navigation from V1.2.
- Large press-and-hold SOS and the older richer card layout.
- GPS coordinates remain visible in SOS/inbox cards.
- `Open map` launches the latest coordinates in the installed map app.
- Location timeline remains available from Inbox.
- No dedicated in-app map tab.
- No Nearby / Safety Presence.
- No Journey Guard.
- SMS is a visible placeholder only; this build requests no SMS permission and sends no SMS.

## V1.4 tracking engine retained

- Android `LocationAccuracy.bestForNavigation`.
- `distanceFilter: 0`.
- Requested ~5 second position interval during an active emergency.
- Foreground emergency location service on Android.
- Separate device heartbeat, GPS-fix and server-sync state.
- Forced GPS refresh if the normal stream is stale.
- Automatic stream restart after an error/completion.
- Offline GPS queue stored locally.
- Connectivity recovery + immediate heartbeat + forced GPS + queued trail replay.
- Batch replay preserves original location timestamps.
- Backend stores speed/heading/liveness timestamps.
- Inbox liveness badge uses heartbeat freshness, not whether coordinates changed.

## Run backend

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python run.py
```

By default the backend uses `./data/viranari.db`. Set `VIRANARI_HOST`, `VIRANARI_PORT`, `VIRANARI_DB_PATH` and `VIRANARI_JWT_SECRET` in `.env` for deployment.

## Run Android app

From the repository root:

```fish
./scripts/prepare_mobile.fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR_API_DOMAIN
```

For a local Android emulator backend use `http://10.0.2.2:3000`.

## Important

The backend tests pass in the packaging environment. Flutter is not installed in that environment, so `flutter analyze` and the Android build must be run on the development machine before relying on the APK.
