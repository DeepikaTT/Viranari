#!/usr/bin/env python3
"""Independently verify a JSON export returned by GET /alerts/{id}/proof.

This does not need the backend private key. The export contains the Ed25519
public key, signed event hashes and all data required to rebuild the hash chain.
"""
from __future__ import annotations

import base64
import hashlib
import json
import sys
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


if len(sys.argv) != 2:
    raise SystemExit("Usage: python tools/verify_proof_export.py proof.json")

proof = json.loads(Path(sys.argv[1]).read_text())
key = Ed25519PublicKey.from_public_bytes(base64.b64decode(proof["public_key_b64"]))
expected_prev = "0" * 64
valid = True

for event in proof.get("events", []):
    created_at = event["created_at"]
    if created_at.endswith("Z"):
        created_at = created_at[:-1] + "+00:00"
    body = {
        "alert_id": proof["alert_id"],
        "sequence": event["sequence"],
        "event_type": event["event_type"],
        "actor_type": event["actor_type"],
        "actor_user_id": event.get("actor_user_id"),
        "payload": event.get("payload", {}),
        "previous_hash": event["previous_hash"],
        "created_at": created_at,
    }
    calculated = sha(canonical(body))
    row_ok = event["previous_hash"] == expected_prev and calculated == event["event_hash"]
    try:
        key.verify(base64.b64decode(event["signature"]), bytes.fromhex(event["event_hash"]))
        sig_ok = True
    except Exception:
        sig_ok = False
    print(f"#{event['sequence']:03d} {event['event_type']}: hash={'OK' if row_ok else 'FAIL'} signature={'OK' if sig_ok else 'FAIL'}")
    valid &= row_ok and sig_ok
    expected_prev = event["event_hash"]

print("VALID" if valid else "INVALID")
raise SystemExit(0 if valid else 2)
