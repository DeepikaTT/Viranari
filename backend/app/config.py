from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    database_path: str = os.getenv("VIRANARI_DB_PATH", "./viranari.db")
    jwt_secret: str = os.getenv("VIRANARI_JWT_SECRET", "CHANGE-ME-IN-REAL-DEPLOYMENTS")
    jwt_issuer: str = "viranari"
    access_token_minutes: int = int(os.getenv("VIRANARI_ACCESS_TOKEN_MINUTES", "720"))
    invite_minutes: int = int(os.getenv("VIRANARI_INVITE_MINUTES", "1440"))


settings = Settings()
