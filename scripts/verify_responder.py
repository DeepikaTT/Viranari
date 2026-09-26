#!/usr/bin/env python3
"""Verify an existing ViraNari user as a SafeReach responder.

Usage:
  VIRANARI_API_BASE=https://api.example.com \
  VIRANARI_ADMIN_KEY=... \
  python scripts/verify_responder.py security@example.com "Campus Security Gate 2" 17.385 78.4867
"""
from __future__ import annotations

import json
import os
import sys
from urllib import request, error

if len(sys.argv) < 5:
    raise SystemExit("Usage: verify_responder.py EMAIL ORGANIZATION LATITUDE LONGITUDE [CATEGORY] [RADIUS_M]")

base = os.getenv("VIRANARI_API_BASE", "http://127.0.0.1:3000").rstrip("/")
admin_key = os.getenv("VIRANARI_ADMIN_KEY")
if not admin_key:
    raise SystemExit("Set VIRANARI_ADMIN_KEY in the shell first.")

email, org, lat, lon = sys.argv[1:5]
category = sys.argv[5] if len(sys.argv) > 5 else "security"
radius = int(sys.argv[6]) if len(sys.argv) > 6 else 5000
payload = json.dumps({
    "user_email": email,
    "organization_name": org,
    "category": category,
    "service_radius_m": radius,
    "latitude": float(lat),
    "longitude": float(lon),
    "is_available": True,
}).encode()
req = request.Request(
    f"{base}/admin/responders/verify",
    data=payload,
    headers={"Content-Type": "application/json", "X-ViraNari-Admin-Key": admin_key},
    method="POST",
)
try:
    with request.urlopen(req, timeout=10) as res:
        print(json.dumps(json.loads(res.read()), indent=2))
except error.HTTPError as exc:
    print(exc.read().decode(), file=sys.stderr)
    raise SystemExit(exc.code)
