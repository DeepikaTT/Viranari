# Upgrade ViraNari V1.3.x → V1.4

## 1. Back up the VPS database

```bash
cd /root/Viranari/backend
cp data/viranari.db "data/backup_$(date +%Y%m%d_%H%M%S).db"
```

Do not delete the database.

## 2. Replace the backend source

Keep your existing `.env`, database and virtual environment if desired. Replace `backend/app`, `backend/run.py`, and `backend/requirements.txt` with the V1.4 versions.

```bash
source venv/bin/activate   # or .venv/bin/activate
pip install -r requirements.txt
python run.py
```

V1.4 runs schema compatibility migration **before** SQLAlchemy creates new indexes/tables. It adds:

- `alerts.last_device_seen_at`
- `alerts.last_gps_fix_at`
- `alerts.last_location_sync_at`
- `journeys` table
- `safety_presence` table

Existing SOS/accounts/contacts are preserved.

## 3. Verify

```bash
curl http://127.0.0.1:3000/health
```

Expected version: `1.4.0`.

```bash
sqlite3 data/viranari.db "PRAGMA table_info(alerts);"
sqlite3 data/viranari.db ".tables"
```

## 4. Rebuild the Flutter wrapper

```fish
cd /path/to/viranari_v1_4
./scripts/prepare_mobile.fish
cd mobile
flutter analyze
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR_API_DOMAIN
```

Rebuilding matters because the native Android SMS bridge changed in V1.4.
