# Upgrade ViraNari V1.4 -> V1.4.1

## VPS

Back up the DB first:

```bash
cd /root/Viranari/backend
cp data/viranari.db "data/backup_$(date +%Y%m%d_%H%M%S).db"
```

Replace the backend `app/`, `run.py`, and `requirements.txt` with V1.4.1, keeping your `.env`, `venv`, and database.

Then:

```bash
source venv/bin/activate
pip install -r requirements.txt
python run.py
```

Check:

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.4.1`.

V1.4.1 creates the new `safety_presence_devices` table automatically. It does not delete your existing emergency data. Journey Guard is no longer exposed; an existing legacy `journeys` table can remain harmlessly in an upgraded SQLite database.

## Android / Flutter

Do not rely on hot reload for this update. SMS permissions and native Kotlin changed.

```fish
cd viranari_v1_4_1
./scripts/prepare_mobile.fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR-API-DOMAIN
```

If an old APK never showed an SMS permission entry, uninstall that old app once, then install the newly rebuilt V1.4.1 build. The installed manifest must contain `android.permission.SEND_SMS` before Android can show/request that permission.
