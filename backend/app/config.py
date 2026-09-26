from __future__ import annotations

import os
import secrets
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()


def _persistent_dev_secret() -> str:
    """Use env in production; otherwise create a private local development key once."""
    env = os.getenv("VIRANARI_JWT_SECRET")
    if env:
        return env
    path = Path(os.getenv("VIRANARI_SECRET_FILE", "./data/.jwt_secret"))
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        value = path.read_text().strip()
        if len(value) >= 64:
            return value
    value = secrets.token_hex(32)
    path.write_text(value)
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return value


def _default_database_path() -> str:
    explicit = os.getenv("VIRANARI_DB_PATH")
    if explicit:
        return explicit
    # Seamless upgrades from earlier hackathon builds.
    for candidate in ("./data/viranari.db", "./viranari.db", "./data/viranari_v12.db"):
        if Path(candidate).exists():
            return candidate
    return "./data/viranari.db"


@dataclass(frozen=True)
class Settings:
    database_path: str = _default_database_path()
    jwt_secret: str = _persistent_dev_secret()
    jwt_issuer: str = "viranari"
    access_token_minutes: int = int(os.getenv("VIRANARI_ACCESS_TOKEN_MINUTES", "720"))
    invite_minutes: int = int(os.getenv("VIRANARI_INVITE_MINUTES", "1440"))
    cors_origins: str = os.getenv("VIRANARI_CORS_ORIGINS", "*")
    admin_key: str = os.getenv("VIRANARI_ADMIN_KEY", "")
    proof_key_path: str = os.getenv("VIRANARI_PROOF_KEY_PATH", "./data/.proof_ed25519.pem")
    responder_location_ttl_minutes: int = int(os.getenv("VIRANARI_RESPONDER_LOCATION_TTL_MINUTES", "30"))
    responder_offer_timeout_seconds: int = int(os.getenv("VIRANARI_RESPONDER_OFFER_TIMEOUT_SECONDS", "60"))


settings = Settings()
