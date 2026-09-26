# Upgrade ViraNari V1.4.3 → V1.5.0

## VPS

Back up the database first:

```bash
cd /root/Viranari/backend
cp data/viranari.db "data/backup_$(date +%Y%m%d_%H%M%S).db"
```

Replace `backend/app/`, `backend/run.py`, `backend/requirements.txt` and add `backend/manage_safe_nodes.py` from V1.5. Keep your existing:
- `backend/.env`
- `backend/venv/`
- `backend/data/viranari.db`
- `backend/data/.jwt_secret` if you use the generated development key.

Then:

```bash
source venv/bin/activate
pip install -r requirements.txt
python run.py
```

V1.5 compatibility migration adds `alerts.silent_mode`. SQLAlchemy creates the new `safety_presence_devices` and `safe_nodes` tables automatically.

Verify:

```bash
curl http://127.0.0.1:3000/health
```

Expected: version `1.5.0`.

## Mobile

V1.5 adds `flutter_compass`; rebuild native wrappers:

```fish
cd viranari_v1_5
./scripts/prepare_mobile.fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter run --dart-define=VIRANARI_API_BASE=https://YOUR_API_DOMAIN
```

## Safe Nodes

Safety Compass deliberately shows nothing if there are no verified Safe Nodes. Add only real, checked locations:

```bash
python manage_safe_nodes.py add \
  --name "Actual Safe Place" \
  --category campus_security \
  --lat REAL_LAT \
  --lon REAL_LON \
  --verified
```

## Safety Map

Nearby dots require mutual opt-in. Enable anonymous presence on both test phones. Presence is installation-scoped, so two physical phones can appear separately even if they use the same account.
