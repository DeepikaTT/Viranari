# Upgrade V1.4.4 → V1.5.0

V1.5.0 is additive. Do not delete your production database.

## Preserve on VPS

```text
backend/.env
backend/data/viranari.db
backend/venv/ or backend/.venv/ (optional)
```

## Replace source, then install the new backend dependency

```bash
cd /root/Viranari/backend
source venv/bin/activate
pip install -r requirements.txt
python run.py
```

The new dependency is `cryptography`, used for Ed25519 ProofChain signatures.

## Add `.env` values

```dotenv
VIRANARI_ADMIN_KEY=<long random secret>
VIRANARI_PROOF_KEY_PATH=./data/.proof_ed25519.pem
VIRANARI_RESPONDER_LOCATION_TTL_MINUTES=30
VIRANARI_RESPONDER_OFFER_TIMEOUT_SECONDS=60
```

The ProofChain private key is generated once if absent. Back it up securely and do not commit it to Git.

## Mobile

```fish
./scripts/prepare_mobile.fish
cd mobile
flutter clean
rm -rf .dart_tool build
flutter pub get
flutter analyze
```

Then run/build using the API domain and emergency-number dart defines documented in README.
