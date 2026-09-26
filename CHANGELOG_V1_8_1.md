# ViraNari V1.8.1 — Safety Map + Responder Trail Fix

- Safety Map now renders category-specific, high-visibility pins for hospitals, police, pharmacies, security and other safe places.
- Public OpenStreetMap lookup keeps up to 100 nearby safety places instead of truncating too aggressively.
- Safe-place distance/bearing are recalculated from the current GPS position so 500 m / 2 km / 5 km filters stay accurate as the user moves.
- Radius camera zoom is widened so the selected search area is actually visible.
- Responder movement is stored as a privacy-scoped SOS breadcrumb trail.
- Live Track removes the misleading straight victim-to-responder connector and draws the responder's actual sampled movement trail instead.
- Backend API adds GET /alerts/{alert_id}/responder-locations.
- Version bumped to 1.8.1+41.
