# Upgrade to ViraNari V1.6.0

1. Back up the current mobile source, backend `.env`, SQLite database and ProofChain private key.
2. Replace application source with V1.6.0 while preserving VPS runtime data.
3. `pip install -r requirements.txt` and restart the API.
4. On mobile run `./scripts/prepare_mobile.fish`, `flutter clean`, `flutter pub get`, then `flutter analyze`.
5. Existing accounts: open **Circle → Your emergency phone → Add/Edit** and save the number in `+countrycode...` format.
6. Open Circle while online once so trusted phone numbers are cached for offline call/SMS fallback.
7. Test: start SOS → disable mobile data → tap **SMS fallback** → verify Messages opens with current coordinates → confirm the live GPS journal count grows while server connectivity is unavailable → reconnect and verify the timeline catches up.

The SMS flow intentionally uses the system composer and requests no `SEND_SMS` permission.
