from __future__ import annotations

from app.config import Settings
from app.main import create_app
from fastapi.testclient import TestClient

from .conftest import auth, register


def _pair(client):
    owner = register(client, "Asha", "asha@example.com")
    contact = register(client, "Maya", "maya@example.com")
    invite = client.post(
        "/contacts/invite",
        headers=auth(owner["access_token"]),
        json={"email": "maya@example.com", "alias": "Sister"},
    )
    assert invite.status_code == 201, invite.text
    token = invite.json()["invite_token"]
    accepted = client.post(
        "/contacts/accept",
        headers=auth(contact["access_token"]),
        json={"invite_token": token},
    )
    assert accepted.status_code == 200, accepted.text
    return owner, contact, invite.json()


def test_01_register_and_me(client):
    user = register(client, "Asha", "asha@example.com")
    me = client.get("/me", headers=auth(user["access_token"]))
    assert me.status_code == 200
    assert me.json()["email"] == "asha@example.com"


def test_02_duplicate_email_rejected(client):
    register(client, "Asha", "asha@example.com")
    r = client.post("/auth/register", json={"name": "Other", "email": "ASHA@example.com", "password": "Password123!"})
    assert r.status_code == 409


def test_03_login(client):
    register(client, "Asha", "asha@example.com")
    r = client.post("/auth/login", json={"email": "asha@example.com", "password": "Password123!"})
    assert r.status_code == 200
    assert r.json()["access_token"]


def test_04_contact_requires_consent(client):
    owner = register(client, "Asha", "asha@example.com")
    contact = register(client, "Maya", "maya@example.com")
    invite = client.post(
        "/contacts/invite",
        headers=auth(owner["access_token"]),
        json={"email": "maya@example.com", "alias": "Sister"},
    ).json()
    listed = client.get("/contacts", headers=auth(owner["access_token"])).json()
    assert listed[0]["status"] == "pending"
    accepted = client.post(
        "/contacts/accept",
        headers=auth(contact["access_token"]),
        json={"invite_token": invite["invite_token"]},
    )
    assert accepted.json()["status"] == "active"


def test_05_idempotent_sos(client):
    owner, _, _ = _pair(client)
    payload = {"idempotency_key": "demo-key-0001", "latitude": 17.385, "longitude": 78.4867, "accuracy_m": 6.0}
    a = client.post("/alerts", headers=auth(owner["access_token"]), json=payload)
    b = client.post("/alerts", headers=auth(owner["access_token"]), json=payload)
    assert a.status_code == 201 and b.status_code == 201
    assert a.json()["id"] == b.json()["id"]
    assert len(a.json()["recipients"]) == 1


def test_06_inbox_marks_delivered(client):
    owner, contact, _ = _pair(client)
    alert = client.post(
        "/alerts",
        headers=auth(owner["access_token"]),
        json={"idempotency_key": "demo-key-0002", "latitude": 17.385, "longitude": 78.4867},
    ).json()
    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"]))
    assert inbox.status_code == 200
    assert inbox.json()[0]["alert_id"] == alert["id"]
    assert inbox.json()[0]["delivered_at"] is not None


def test_07_acknowledgement_visible_to_sender(client):
    owner, contact, _ = _pair(client)
    alert = client.post(
        "/alerts",
        headers=auth(owner["access_token"]),
        json={"idempotency_key": "demo-key-0003", "latitude": 17.385, "longitude": 78.4867},
    ).json()
    client.get("/alerts/inbox", headers=auth(contact["access_token"]))
    ack = client.post(f"/alerts/{alert['id']}/acknowledge", headers=auth(contact["access_token"]))
    assert ack.status_code == 200
    status = client.get(f"/alerts/detail/{alert['id']}", headers=auth(owner["access_token"]))
    assert status.json()["recipients"][0]["acknowledged_at"] is not None


def test_08_unauthorized_user_cannot_read_alert(client):
    owner, _, _ = _pair(client)
    stranger = register(client, "Riya", "riya@example.com")
    alert = client.post(
        "/alerts",
        headers=auth(owner["access_token"]),
        json={"idempotency_key": "demo-key-0004", "latitude": 17.385, "longitude": 78.4867},
    ).json()
    r = client.get(f"/alerts/detail/{alert['id']}", headers=auth(stranger["access_token"]))
    assert r.status_code == 403


def test_09_removed_contact_gets_no_new_alerts(client):
    owner, contact, contact_record = _pair(client)
    rm = client.delete(f"/contacts/{contact_record['id']}", headers=auth(owner["access_token"]))
    assert rm.status_code == 200
    alert = client.post(
        "/alerts",
        headers=auth(owner["access_token"]),
        json={"idempotency_key": "demo-key-0005", "latitude": 17.385, "longitude": 78.4867},
    ).json()
    assert alert["recipients"] == []
    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"])).json()
    assert inbox == []


def test_10_persistence_across_app_restart(tmp_path):
    db = str(tmp_path / "persist.db")
    cfg = Settings(database_path=db, jwt_secret="persist-secret-0123456789-0123456789")
    app1 = create_app(database_path=db, settings=cfg)
    with TestClient(app1) as c1:
        owner = register(c1, "Asha", "asha@example.com")
        c1.post(
            "/alerts",
            headers=auth(owner["access_token"]),
            json={"idempotency_key": "persist-key-01", "latitude": 17.385, "longitude": 78.4867},
        )
    app2 = create_app(database_path=db, settings=cfg)
    with TestClient(app2) as c2:
        login = c2.post("/auth/login", json={"email": "asha@example.com", "password": "Password123!"}).json()
        history = c2.get("/alerts/history", headers=auth(login["access_token"])).json()
        assert len(history) == 1
        assert history[0]["idempotency_key"] == "persist-key-01"
