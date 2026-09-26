# Upgrade to ViraNari V1.4.4

V1.4.4 is primarily a mobile UI rollback/merge. It keeps the V1.4 backend/location protocol.

## VPS

1. Back up the SQLite database.
2. Keep `.env`, `venv/` and the database.
3. Replace `backend/app/`, `backend/run.py`, and `backend/requirements.txt` with this release.
4. Restart and verify `/health` reports `1.4.4`.

Example:

```bash
cd /root/Viranari/backend
cp data/viranari.db "data/backup_$(date +%Y%m%d_%H%M%S).db"
source venv/bin/activate
pip install -r requirements.txt
python run.py
```

## Android

Recreate/patch the wrapper and perform a clean rebuild:

```fish
cd ~/Downloads/viranari_v1_4_4
./scripts/prepare_mobile.fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR_API_DOMAIN
```

SMS is only a placeholder in this build; no SMS permission should appear.
