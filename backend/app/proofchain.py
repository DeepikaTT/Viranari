from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_hex(value: str | bytes) -> str:
    data = value.encode("utf-8") if isinstance(value, str) else value
    return hashlib.sha256(data).hexdigest()


class ProofSigner:
    """Persistent Ed25519 signer for incident ProofChain events.

    The private key stays on the backend. Clients receive the public key and can
    independently verify every signature and hash-chain link.
    """

    def __init__(self, key_path: str):
        self.key_path = Path(key_path)
        self.key_path.parent.mkdir(parents=True, exist_ok=True)
        self._private = self._load_or_create()
        self._public = self._private.public_key()

    def _load_or_create(self) -> Ed25519PrivateKey:
        if self.key_path.exists():
            raw = self.key_path.read_bytes()
            return serialization.load_pem_private_key(raw, password=None)
        key = Ed25519PrivateKey.generate()
        raw = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        self.key_path.write_bytes(raw)
        try:
            os.chmod(self.key_path, 0o600)
        except OSError:
            pass
        return key

    @property
    def key_id(self) -> str:
        return sha256_hex(self.public_key_raw())[:16]

    def public_key_raw(self) -> bytes:
        return self._public.public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )

    def public_key_b64(self) -> str:
        return base64.b64encode(self.public_key_raw()).decode("ascii")

    def sign_hash(self, event_hash: str) -> str:
        return base64.b64encode(self._private.sign(bytes.fromhex(event_hash))).decode("ascii")

    def verify_hash(self, event_hash: str, signature_b64: str) -> bool:
        try:
            self._public.verify(base64.b64decode(signature_b64), bytes.fromhex(event_hash))
            return True
        except Exception:
            return False


def verify_with_public_key(public_key_b64: str, event_hash: str, signature_b64: str) -> bool:
    try:
        key = Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key_b64))
        key.verify(base64.b64decode(signature_b64), bytes.fromhex(event_hash))
        return True
    except Exception:
        return False
