# Upgrade to V1.8

Back up the VPS database first. Keep `.env`, your virtual environment and `backend/data/viranari.db`.

V1.8 adds the `responder_locations` table automatically through SQLAlchemy `create_all`; existing tables/data are preserved.

After updating backend source:

```bash
cd /root/Viranari/backend
python run.py
curl http://127.0.0.1:3000/health
```

Expected API version: `1.8.1`.

Mobile:

```fish
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter build apk --release
```

The Android package version is `1.8.1+41`.
