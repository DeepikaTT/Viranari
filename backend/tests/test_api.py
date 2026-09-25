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


def _alert(client, owner, key="demo-key-0001"):
    return client.post(
        "/alerts",
        headers=auth(owner["access_token"]),
        json={
            "idempotency_key": key,
            "latitude": 17.385,
            "longitude": 78.4867,
            "accuracy_m": 6.0,
            "battery_percent": 72,
            "network_state": "wifi",
        },
    )


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
    a = _alert(client, owner, "demo-key-0001")
    b = _alert(client, owner, "demo-key-0001")
    assert a.status_code == 201 and b.status_code == 201
    assert a.json()["id"] == b.json()["id"]
    assert len(a.json()["recipients"]) == 1


def test_06_inbox_marks_delivered(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "demo-key-0002").json()
    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"]))
    assert inbox.status_code == 200
    assert inbox.json()[0]["alert_id"] == alert["id"]
    assert inbox.json()[0]["delivered_at"] is not None


def test_07_acknowledgement_visible_to_sender(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "demo-key-0003").json()
    client.get("/alerts/inbox", headers=auth(contact["access_token"]))
    ack = client.post(f"/alerts/{alert['id']}/acknowledge", headers=auth(contact["access_token"]))
    assert ack.status_code == 200
    status = client.get(f"/alerts/detail/{alert['id']}", headers=auth(owner["access_token"]))
    assert status.json()["recipients"][0]["acknowledged_at"] is not None


def test_08_unauthorized_user_cannot_read_alert(client):
    owner, _, _ = _pair(client)
    stranger = register(client, "Riya", "riya@example.com")
    alert = _alert(client, owner, "demo-key-0004").json()
    r = client.get(f"/alerts/detail/{alert['id']}", headers=auth(stranger["access_token"]))
    assert r.status_code == 403


def test_09_removed_contact_gets_no_new_alerts(client):
    owner, contact, contact_record = _pair(client)
    rm = client.delete(f"/contacts/{contact_record['id']}", headers=auth(owner["access_token"]))
    assert rm.status_code == 200
    alert = _alert(client, owner, "demo-key-0005").json()
    assert alert["recipients"] == []
    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"])).json()
    assert inbox == []


def test_10_live_location_updates_visible_to_recipient(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "live-key-0001").json()
    update = client.post(
        f"/alerts/{alert['id']}/location",
        headers=auth(owner["access_token"]),
        json={
            "latitude": 17.391,
            "longitude": 78.491,
            "accuracy_m": 4.5,
            "battery_percent": 55,
            "network_state": "mobile",
        },
    )
    assert update.status_code == 200
    assert update.json()["latitude"] == 17.391
    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"])).json()
    assert inbox[0]["latitude"] == 17.391
    assert inbox[0]["battery_percent"] == 55
    assert inbox[0]["network_state"] == "mobile"


def test_11_location_timeline_is_persistent(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "live-key-0002").json()
    for n in range(2):
        client.post(
            f"/alerts/{alert['id']}/location",
            headers=auth(owner["access_token"]),
            json={"latitude": 17.385 + n * 0.001, "longitude": 78.4867 + n * 0.001},
        )
    timeline = client.get(f"/alerts/{alert['id']}/locations", headers=auth(contact["access_token"]))
    assert timeline.status_code == 200
    assert len(timeline.json()) == 3  # initial location + two updates


def test_12_active_alert_endpoint_and_resolve(client):
    owner, _, _ = _pair(client)
    alert = _alert(client, owner, "active-key-01").json()
    active = client.get("/alerts/active", headers=auth(owner["access_token"]))
    assert active.status_code == 200
    assert active.json()["id"] == alert["id"]
    resolved = client.post(f"/alerts/{alert['id']}/resolve", headers=auth(owner["access_token"]))
    assert resolved.status_code == 200
    assert resolved.json()["state"] == "resolved"
    missing = client.get("/alerts/active", headers=auth(owner["access_token"]))
    assert missing.status_code == 404


def test_13_cancelled_alert_rejects_location_updates(client):
    owner, _, _ = _pair(client)
    alert = _alert(client, owner, "cancel-key-01").json()
    cancelled = client.post(f"/alerts/{alert['id']}/cancel", headers=auth(owner["access_token"]))
    assert cancelled.status_code == 200
    assert cancelled.json()["state"] == "cancelled"
    update = client.post(
        f"/alerts/{alert['id']}/location",
        headers=auth(owner["access_token"]),
        json={"latitude": 17.4, "longitude": 78.5},
    )
    assert update.status_code == 409


def test_14_recipient_cannot_end_owner_session(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "owner-only-01").json()
    r = client.post(f"/alerts/{alert['id']}/resolve", headers=auth(contact["access_token"]))
    assert r.status_code == 404


def test_15_persistence_across_app_restart(tmp_path):
    db = str(tmp_path / "persist.db")
    cfg = Settings(database_path=db, jwt_secret="persist-secret-0123456789-0123456789")
    app1 = create_app(database_path=db, settings=cfg)
    with TestClient(app1) as c1:
        owner = register(c1, "Asha", "asha@example.com")
        alert = _alert(c1, owner, "persist-key-01").json()
        c1.post(
            f"/alerts/{alert['id']}/location",
            headers=auth(owner["access_token"]),
            json={"latitude": 17.399, "longitude": 78.499, "battery_percent": 44},
        )
    app2 = create_app(database_path=db, settings=cfg)
    with TestClient(app2) as c2:
        login = c2.post("/auth/login", json={"email": "asha@example.com", "password": "Password123!"}).json()
        history = c2.get("/alerts/history", headers=auth(login["access_token"])).json()
        assert len(history) == 1
        assert history[0]["latitude"] == 17.399
        timeline = c2.get(f"/alerts/{history[0]['id']}/locations", headers=auth(login["access_token"])).json()
        assert len(timeline) == 2


def test_16_test_drill_is_clearly_labelled(client):
    owner, contact, _ = _pair(client)
    alert = client.post(
        "/alerts",
        headers=auth(owner["access_token"]),
        json={
            "idempotency_key": "test-drill-0001",
            "latitude": 17.385,
            "longitude": 78.4867,
            "is_test": True,
            "note": "Practice alert",
        },
    ).json()
    assert alert["is_test"] is True
    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"])).json()
    assert inbox[0]["is_test"] is True


def test_17_multiple_trusted_contacts_receive_same_alert(client):
    owner = register(client, "Asha", "asha@example.com")
    maya = register(client, "Maya", "maya@example.com")
    riya = register(client, "Riya", "riya@example.com")
    for contact, email, alias in [(maya, "maya@example.com", "Sister"), (riya, "riya@example.com", "Friend")]:
        invite = client.post(
            "/contacts/invite",
            headers=auth(owner["access_token"]),
            json={"email": email, "alias": alias},
        ).json()
        accepted = client.post(
            "/contacts/accept",
            headers=auth(contact["access_token"]),
            json={"invite_token": invite["invite_token"]},
        )
        assert accepted.status_code == 200

    alert = client.post(
        "/alerts",
        headers=auth(owner["access_token"]),
        json={"idempotency_key": "multi-contact-01", "latitude": 17.385, "longitude": 78.4867},
    ).json()
    assert len(alert["recipients"]) == 2
    assert len(client.get("/alerts/inbox", headers=auth(maya["access_token"])).json()) == 1
    assert len(client.get("/alerts/inbox", headers=auth(riya["access_token"])).json()) == 1
