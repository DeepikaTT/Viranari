# Android Emulator demo

ViraNari still uses normal Android runtime permissions in production. For hackathon emulator testing, the included scripts remove most manual tapping by granting permissions through ADB and injecting mock GPS coordinates into the emulator.

```fish
./scripts/emulator_prepare_demo.fish
./scripts/emulator_route_demo.fish
```

Use two emulators (or one emulator + one phone) to demonstrate victim/responder distance. Start an SOS on the victim, accept it on the responder, then run the route script on the victim emulator.
