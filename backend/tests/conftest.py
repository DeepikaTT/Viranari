from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


@pytest.fixture()
def client(tmp_path: Path):
    cfg = Settings(database_path=str(tmp_path / "test.db"), jwt_secret="test-secret-0123456789-0123456789-xx")
    app = create_app(database_path=cfg.database_path, settings=cfg)
    with TestClient(app) as c:
        yield c


def register(client, name: str, email: str, password: str = "Password123!", phone_e164: str | None = None):
    payload = {"name": name, "email": email, "password": password}
    if phone_e164 is not None:
        payload["phone_e164"] = phone_e164
    r = client.post("/auth/register", json=payload)
    assert r.status_code == 201, r.text
    return r.json()


def auth(token: str):
    return {"Authorization": f"Bearer {token}"}
