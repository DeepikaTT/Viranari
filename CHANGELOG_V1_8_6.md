# ViraNari V1.8.6 — Precision Coordination

V1.8.6 is a focused polish/reliability update on top of V1.8.5.

## Emergency Active UI

- Cleaner compact Emergency Active card.
- Professional victim/responder markers with clearer role labels.
- Exactly one blue live-separation connector on the Home emergency map.
- Three high-visibility metrics: live distance, approximate ETA, and combined GPS precision.
- ETA is visible on both the victim Home screen and the responder Live Track screen.
- Nearby responder banner remains when the responder comes within 100 m.
- Coordinates and last responder freshness stay available without dominating the card.

## More reliable responder GPS

- Responder tracking now uses a continuous best-for-navigation GPS stream instead of requesting a brand-new one-shot GPS fix every 3 seconds.
- A transient GPS warm-up timeout falls back to a recent last-known/previous reliable fix.
- Very poor GPS fixes (>100 m accuracy when a better point already exists) are held back so distance does not jump wildly.
- Server upload failures keep the last reliable responder marker/ETA visible and retry on the next GPS update.
- The victim's emergency refresh no longer fails as a whole if only the responder-location request is temporarily slow.

## Distance / ETA

- Separation is recalculated from the latest victim + responder coordinates using geodesic GPS distance.
- Combined GPS uncertainty is shown as ± metres when available.
- ETA remains approximate because it is based on current measured responder speed (or a conservative fallback pace), not road-routing/navigation.

## Safety Map radius fix

- 500 m / 2 km / 5 km now immediately changes the anonymous-device map zoom.
- Anonymous dots are locally filtered immediately and then re-queried from the server for the selected radius.
- A user radius change is no longer dropped when the 7-second background refresh happens at the same time.
- Hospitals/police/pharmacies remain independent from the people-radius selector and stay available out to the safety-place search radius.

Mobile version: `1.8.6+46`  
Backend API version: `1.8.6`
