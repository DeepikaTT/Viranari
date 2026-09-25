# Upgrade from ViraNari v1.2 to v1.3

## Why the old v1.2 database previously failed

SQLAlchemy `create_all()` creates missing tables but does not add new columns to an existing SQLite table. v1.3 includes a compatibility migration layer so the normal startup upgrades the v1/v1.2 schema in-place.

v1.3 adds:
- `users.phone_e164`
- `alert_locations.speed_mps`
- `alert_locations.heading_deg`
- `schema_migrations` bookkeeping table

## Recommended VPS upgrade

Stop the old backend and back up the database first:

```bash
cd /root/Viranari/backend
cp viranari.db viranari.db.backup-$(date +%F-%H%M%S) 2>/dev/null || true
cp data/viranari_v12.db data/viranari_v12.db.backup-$(date +%F-%H%M%S) 2>/dev/null || true
```

Copy the v1.3 source over, then point the new release at the database you actually want to preserve:

```bash
export VIRANARI_DB_PATH=/root/Viranari/backend/viranari.db
```

or, if your old run script used the data directory:

```bash
export VIRANARI_DB_PATH=/root/Viranari/backend/data/viranari_v12.db
```

Install updated requirements and start:

```bash
source venv/bin/activate   # or your existing venv
pip install -r requirements.txt
python run.py
```

On startup v1.3 checks existing columns and applies only missing compatibility changes. **Do not delete the old database just to upgrade.**

Verify:

```bash
curl http://127.0.0.1:3000/health
```

Expected:

```json
{"status":"ok","service":"viranari-api","version":"1.3.0"}
```

## JWT secret

Use a real secret on the VPS:

```bash
python -c 'import secrets; print(secrets.token_hex(32))'
```

Put it in `.env` as `VIRANARI_JWT_SECRET=...`.

Changing the JWT secret signs users out, but does not delete database records.
