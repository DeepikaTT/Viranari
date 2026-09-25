# Upgrade to ViraNari V1.4.2

## VPS

Back up the SQLite database first:

```bash
cd /root/Viranari/backend
cp data/viranari.db "data/backup_$(date +%Y%m%d_%H%M%S).db"
```

Replace `backend/app/`, `backend/run.py`, and `backend/requirements.txt` with the V1.4.2 versions. Keep your `.env`, `venv`, and database.

```bash
source venv/bin/activate
pip install -r requirements.txt
python run.py
```

Verify:

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.4.2`.

The old Safety Presence database table can remain harmlessly in an existing DB; V1.4.2 no longer exposes or uses the feature.

## Android / Flutter

V1.4.2 removes SEND_SMS and the custom SMS MethodChannel, so recreate/patch the platform wrapper and rebuild rather than hot-reloading an old APK:

```fish
cd viranari_v1_4_2
./scripts/prepare_mobile.fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR-API-DOMAIN
```

If Android still shows stale permissions from an old build, uninstall once and reinstall the rebuilt app.
