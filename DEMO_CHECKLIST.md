# ViraNari v1.2 demo checklist

- [ ] Backend `/health` returns version `1.2.0`
- [ ] `./scripts/test_backend.fish` passes
- [ ] Pixel emulator boots
- [ ] App registers/logs in
- [ ] Two accounts can consent into Trusted Circle
- [ ] Practice Mode sends a clearly labelled TEST alert
- [ ] Real SOS captures emulator/phone GPS
- [ ] Emergency shows ACTIVE immediately
- [ ] Recipient inbox receives alert while app is running
- [ ] Sender shows SENT / DELIVERED / ACKNOWLEDGED accurately
- [ ] Change emulator location and verify `Last location` updates
- [ ] Open map from recipient alert
- [ ] End emergency with `I'm safe`
- [ ] Turn backend off, trigger SOS, verify offline retry queue
- [ ] Restart backend and verify queue reconciliation
- [ ] Test low battery display if physical device/emulator permits
- [ ] Explain that push background reception needs Firebase/APNs credentials; do not fake it
