from __future__ import annotations

from datetime import datetime, timedelta
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


def test_18_phone_number_can_be_registered_and_updated(client):
    user = register(client, "Asha", "asha@example.com", phone_e164="+919876543210")
    assert user["user"]["phone_e164"] == "+919876543210"
    updated = client.patch(
        "/me/phone",
        headers=auth(user["access_token"]),
        json={"phone_e164": "+919999888877"},
    )
    assert updated.status_code == 200
    assert updated.json()["phone_e164"] == "+919999888877"


def test_19_pending_contact_phone_is_private_until_consent(client):
    owner = register(client, "Asha", "asha@example.com", phone_e164="+919111111111")
    contact = register(client, "Maya", "maya@example.com", phone_e164="+919222222222")
    invite = client.post(
        "/contacts/invite",
        headers=auth(owner["access_token"]),
        json={"email": "maya@example.com", "alias": "Sister"},
    )
    assert invite.status_code == 201
    assert invite.json()["contact_phone_e164"] is None
    accepted = client.post(
        "/contacts/accept",
        headers=auth(contact["access_token"]),
        json={"invite_token": invite.json()["invite_token"]},
    )
    assert accepted.status_code == 200
    listed = client.get("/contacts", headers=auth(owner["access_token"])).json()
    assert listed[0]["contact_phone_e164"] == "+919222222222"


def test_20_recipient_can_call_sender_number_during_sos(client):
    owner = register(client, "Asha", "asha@example.com", phone_e164="+919111111111")
    contact = register(client, "Maya", "maya@example.com", phone_e164="+919222222222")
    invite = client.post(
        "/contacts/invite",
        headers=auth(owner["access_token"]),
        json={"email": "maya@example.com", "alias": "Sister"},
    ).json()
    client.post(
        "/contacts/accept",
        headers=auth(contact["access_token"]),
        json={"invite_token": invite["invite_token"]},
    )
    _alert(client, owner, "sender-phone-01")
    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"]))
    assert inbox.status_code == 200
    assert inbox.json()[0]["sender_phone_e164"] == "+919111111111"


def test_21_location_speed_heading_and_utc_are_preserved(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "live-motion-01").json()
    update = client.post(
        f"/alerts/{alert['id']}/location",
        headers=auth(owner["access_token"]),
        json={
            "latitude": 17.401,
            "longitude": 78.501,
            "accuracy_m": 3.0,
            "battery_percent": 51,
            "network_state": "mobile",
            "speed_mps": 1.5,
            "heading_deg": 42.0,
        },
    )
    assert update.status_code == 200
    timeline = client.get(f"/alerts/{alert['id']}/locations", headers=auth(contact["access_token"]))
    assert timeline.status_code == 200
    latest = timeline.json()[-1]
    assert latest["speed_mps"] == 1.5
    assert latest["heading_deg"] == 42.0
    # API timestamps must carry an explicit UTC offset so Flutter can safely .toLocal().
    assert latest["recorded_at"].endswith("Z") or "+00:00" in latest["recorded_at"]


def test_22_existing_v12_sqlite_schema_is_upgraded_in_place(tmp_path):
    import sqlite3

    db_path = tmp_path / "old.db"
    conn = sqlite3.connect(db_path)
    conn.executescript(
        """
        CREATE TABLE users (
            id VARCHAR(36) PRIMARY KEY,
            name VARCHAR(80),
            email VARCHAR(255),
            password_hash TEXT,
            created_at DATETIME
        );
        CREATE TABLE alert_locations (
            id VARCHAR(36) PRIMARY KEY,
            alert_id VARCHAR(36),
            latitude FLOAT,
            longitude FLOAT,
            accuracy_m FLOAT,
            battery_percent INTEGER,
            network_state VARCHAR(40),
            recorded_at DATETIME
        );
        """
    )
    conn.commit()
    conn.close()

    from app.db import apply_compat_migrations, build_engine

    engine = build_engine(str(db_path))
    apply_compat_migrations(engine)
    conn = sqlite3.connect(db_path)
    user_cols = {row[1] for row in conn.execute("PRAGMA table_info(users)")}
    loc_cols = {row[1] for row in conn.execute("PRAGMA table_info(alert_locations)")}
    conn.close()
    assert "phone_e164" in user_cols
    assert "speed_mps" in loc_cols
    assert "heading_deg" in loc_cols


def test_23_existing_v1_alert_table_gets_all_session_columns(tmp_path):
    import sqlite3

    db_path = tmp_path / "v1-old.db"
    conn = sqlite3.connect(db_path)
    conn.executescript(
        """
        CREATE TABLE alerts (
            id VARCHAR(36) PRIMARY KEY,
            owner_id VARCHAR(36),
            idempotency_key VARCHAR(100),
            latitude FLOAT,
            longitude FLOAT,
            accuracy_m FLOAT,
            battery_percent INTEGER,
            note TEXT,
            created_at DATETIME
        );
        INSERT INTO alerts(
            id, owner_id, idempotency_key, latitude, longitude,
            accuracy_m, battery_percent, note, created_at
        ) VALUES (
            'a1', 'u1', 'idem-1', 17.0, 78.0, 5.0, 50, 'old',
            '2026-09-25 12:00:00'
        );
        """
    )
    conn.commit()
    conn.close()

    from app.db import apply_compat_migrations, build_engine

    engine = build_engine(str(db_path))
    apply_compat_migrations(engine)

    conn = sqlite3.connect(db_path)
    cols = {row[1] for row in conn.execute("PRAGMA table_info(alerts)")}
    row = conn.execute(
        "SELECT network_state, is_test, state, updated_at, cancelled_at, resolved_at "
        "FROM alerts WHERE id='a1'"
    ).fetchone()
    conn.close()

    assert {
        "network_state", "is_test", "state", "updated_at",
        "cancelled_at", "resolved_at"
    }.issubset(cols)
    assert row[0] is None
    assert row[1] == 0
    assert row[2] == "active"
    assert row[3] == "2026-09-25 12:00:00"
    assert row[4] is None
    assert row[5] is None


def test_24_offline_location_batch_replays_original_timestamps(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "batch-replay-01").json()
    created = datetime.fromisoformat(alert["created_at"].replace("Z", "+00:00"))
    t1 = created + timedelta(seconds=5)
    t2 = created + timedelta(seconds=10)
    r = client.post(
        f"/alerts/{alert['id']}/locations/batch",
        headers=auth(owner["access_token"]),
        json={
            "points": [
                {
                    "latitude": 17.390,
                    "longitude": 78.490,
                    "accuracy_m": 5.0,
                    "battery_percent": 49,
                    "network_state": "offline",
                    "speed_mps": 1.2,
                    "heading_deg": 30.0,
                    "recorded_at": t1.isoformat(),
                },
                {
                    "latitude": 17.391,
                    "longitude": 78.491,
                    "accuracy_m": 4.0,
                    "battery_percent": 48,
                    "network_state": "offline",
                    "speed_mps": 1.4,
                    "heading_deg": 35.0,
                    "recorded_at": t2.isoformat(),
                },
            ]
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["accepted"] == 2
    timeline = client.get(f"/alerts/{alert['id']}/locations", headers=auth(contact["access_token"]))
    assert timeline.status_code == 200
    points = timeline.json()
    assert len(points) == 3
    assert points[-2]["recorded_at"].startswith(t1.replace(tzinfo=None).isoformat())
    assert points[-1]["recorded_at"].startswith(t2.replace(tzinfo=None).isoformat())
    assert points[-1]["latitude"] == 17.391


def test_25_heartbeat_keeps_device_live_without_adding_location(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "heartbeat-01").json()
    before = client.get(f"/alerts/{alert['id']}/locations", headers=auth(contact["access_token"])).json()
    beat = client.post(
        f"/alerts/{alert['id']}/heartbeat",
        headers=auth(owner["access_token"]),
        json={"battery_percent": 61, "network_state": "mobile", "last_gps_fix_at": alert["created_at"]},
    )
    assert beat.status_code == 200, beat.text
    payload = beat.json()
    assert payload["last_device_seen_at"] is not None
    assert payload["battery_percent"] == 61
    after = client.get(f"/alerts/{alert['id']}/locations", headers=auth(contact["access_token"])).json()
    assert len(after) == len(before)  # heartbeat is liveness, not a fake GPS sample


def test_26_inbox_exposes_liveness_timestamps(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "heartbeat-inbox-01").json()
    client.post(
        f"/alerts/{alert['id']}/heartbeat",
        headers=auth(owner["access_token"]),
        json={"battery_percent": 60, "network_state": "wifi", "last_gps_fix_at": alert["created_at"]},
    )
    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"]))
    assert inbox.status_code == 200
    row = inbox.json()[0]
    assert row["last_device_seen_at"] is not None
    assert row["last_gps_fix_at"] is not None
    assert row["last_location_sync_at"] is not None


def test_27_v13_database_migrates_heartbeat_columns(tmp_path):
    import sqlite3
    from app.db import apply_compat_migrations, build_engine

    db_path = tmp_path / "v13.db"
    conn = sqlite3.connect(db_path)
    conn.executescript(
        """
        CREATE TABLE alerts (
            id VARCHAR(36) PRIMARY KEY,
            owner_id VARCHAR(36), idempotency_key VARCHAR(100),
            latitude FLOAT, longitude FLOAT, accuracy_m FLOAT,
            battery_percent INTEGER, network_state VARCHAR(40), is_test BOOLEAN,
            note TEXT, state VARCHAR(20), created_at DATETIME, updated_at DATETIME,
            cancelled_at DATETIME, resolved_at DATETIME
        );
        INSERT INTO alerts(id, owner_id, idempotency_key, latitude, longitude, state, created_at, updated_at)
        VALUES('a1','u1','idem',17,78,'active','2026-09-25 12:00:00','2026-09-25 12:01:00');
        """
    )
    conn.commit(); conn.close()
    engine = build_engine(str(db_path))
    apply_compat_migrations(engine)
    conn = sqlite3.connect(db_path)
    cols = {row[1] for row in conn.execute("PRAGMA table_info(alerts)")}
    row = conn.execute("SELECT last_device_seen_at,last_gps_fix_at,last_location_sync_at FROM alerts WHERE id='a1'").fetchone()
    conn.close()
    assert {"last_device_seen_at", "last_gps_fix_at", "last_location_sync_at"}.issubset(cols)
    assert row == ("2026-09-25 12:01:00", "2026-09-25 12:01:00", "2026-09-25 12:01:00")


def test_32_create_app_upgrades_existing_alert_schema_before_indexes(tmp_path):
    import sqlite3

    db_path = tmp_path / "upgrade-startup.db"
    conn = sqlite3.connect(db_path)
    conn.executescript(
        """
        CREATE TABLE users (
            id VARCHAR(36) PRIMARY KEY,
            name VARCHAR(80), email VARCHAR(255), phone_e164 VARCHAR(16),
            password_hash TEXT, created_at DATETIME
        );
        CREATE TABLE alerts (
            id VARCHAR(36) PRIMARY KEY,
            owner_id VARCHAR(36), idempotency_key VARCHAR(100), latitude FLOAT, longitude FLOAT,
            accuracy_m FLOAT, battery_percent INTEGER, network_state VARCHAR(40), is_test BOOLEAN,
            note TEXT, state VARCHAR(20), created_at DATETIME, updated_at DATETIME,
            cancelled_at DATETIME, resolved_at DATETIME
        );
        CREATE TABLE alert_locations (
            id VARCHAR(36) PRIMARY KEY, alert_id VARCHAR(36), latitude FLOAT, longitude FLOAT,
            accuracy_m FLOAT, battery_percent INTEGER, network_state VARCHAR(40), speed_mps FLOAT,
            heading_deg FLOAT, recorded_at DATETIME
        );
        """
    )
    conn.commit(); conn.close()

    cfg = Settings(database_path=str(db_path), jwt_secret="startup-upgrade-secret-0123456789012345")
    app = create_app(database_path=str(db_path), settings=cfg)
    with TestClient(app) as c:
        assert c.get("/health").status_code == 200

    conn = sqlite3.connect(db_path)
    cols = {row[1] for row in conn.execute("PRAGMA table_info(alerts)")}
    user_cols = {row[1] for row in conn.execute("PRAGMA table_info(users)")}
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    conn.close()
    assert {"last_device_seen_at", "last_gps_fix_at", "last_location_sync_at"}.issubset(cols)
    assert "role" in user_cols
    assert {"responder_profiles", "responder_assignments", "incident_events"}.issubset(tables)


def _verified_responder(client, email="guard@example.com", lat=17.386, lon=78.487):
    responder = register(client, "Campus Guard", email, phone_e164="+919876543210")
    verified = client.post(
        "/admin/responders/verify",
        headers={"X-ViraNari-Admin-Key": "test-admin-key"},
        json={
            "user_email": email,
            "organization_name": "Campus Security Gate 2",
            "category": "campus_security",
            "service_radius_m": 5000,
            "latitude": lat,
            "longitude": lon,
            "is_available": True,
        },
    )
    assert verified.status_code == 200, verified.text
    return responder, verified.json()


def test_29_safe_reach_auto_matches_verified_nearby_responder(client):
    responder, profile = _verified_responder(client)
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "safe-reach-0001")
    assert alert.status_code == 201, alert.text
    assignment = alert.json()["safe_reach"]
    assert assignment is not None
    assert assignment["organization_name"] == "Campus Security Gate 2"
    assert assignment["state"] == "offered"
    assert assignment["distance_m"] < 5000

    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"]))
    assert inbox.status_code == 200
    assert inbox.json()[0]["safe_reach"]["organization_name"] == "Campus Security Gate 2"

    incidents = client.get("/responders/incidents", headers=auth(responder["access_token"]))
    assert incidents.status_code == 200
    assert incidents.json()[0]["alert_id"] == alert.json()["id"]


def test_30_responder_status_transitions_and_proofchain_verify(client):
    responder, _ = _verified_responder(client)
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "safe-reach-0002").json()

    accepted = client.post(f"/responders/incidents/{alert['id']}/accept", headers=auth(responder["access_token"]))
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["state"] == "accepted"

    arrived = client.post(f"/responders/incidents/{alert['id']}/arrive", headers=auth(responder["access_token"]))
    assert arrived.status_code == 200, arrived.text
    assert arrived.json()["state"] == "arrived"

    proof = client.get(f"/alerts/{alert['id']}/proof", headers=auth(contact["access_token"]))
    assert proof.status_code == 200, proof.text
    types = [e["event_type"] for e in proof.json()["events"]]
    assert "SOS_CREATED" in types
    assert "SAFE_REACH_RESPONDER_MATCHED" in types
    assert "SAFE_REACH_ACCEPTED" in types
    assert "SAFE_REACH_ARRIVED" in types

    verified = client.get(f"/alerts/{alert['id']}/proof/verify", headers=auth(owner["access_token"]))
    assert verified.status_code == 200, verified.text
    assert verified.json()["valid"] is True
    assert verified.json()["hash_chain_valid"] is True
    assert verified.json()["signatures_valid"] is True
    assert verified.json()["event_count"] >= 5


def test_31_unverified_user_cannot_use_responder_console(client):
    user = register(client, "Random User", "random@example.com")
    r = client.get("/responders/me", headers=auth(user["access_token"]))
    assert r.status_code == 403


def test_32_admin_key_required_for_responder_verification(client):
    register(client, "Guard", "guard2@example.com")
    r = client.post(
        "/admin/responders/verify",
        json={
            "user_email": "guard2@example.com",
            "organization_name": "Security Desk",
            "category": "security",
            "service_radius_m": 3000,
            "latitude": 17.385,
            "longitude": 78.4867,
            "is_available": True,
        },
    )
    assert r.status_code == 403


def test_33_proofchain_detects_database_tamper(client):
    owner = register(client, "Asha", "asha@example.com")
    alert = _alert(client, owner, "proof-tamper-01").json()
    app = client.app
    SessionLocal = app.state.SessionLocal
    from app.models import IncidentEvent
    from sqlalchemy import select
    with SessionLocal() as db:
        event = db.scalar(select(IncidentEvent).where(IncidentEvent.alert_id == alert["id"]).order_by(IncidentEvent.sequence.asc()))
        event.payload_json = '{"recipient_count":999}'
        db.commit()
    verified = client.get(f"/alerts/{alert['id']}/proof/verify", headers=auth(owner["access_token"]))
    assert verified.status_code == 200
    assert verified.json()["valid"] is False
    assert verified.json()["hash_chain_valid"] is False


def test_34_decline_automatically_rematches_without_leaking_new_assignment(client):
    responder1, _ = _verified_responder(client, email="guard1@example.com", lat=17.3852, lon=78.4868)
    responder2, _ = _verified_responder(client, email="guard2@example.com", lat=17.3865, lon=78.4880)
    owner = register(client, "Asha", "asha@example.com")
    alert = _alert(client, owner, "safe-rematch-01").json()
    first_profile = alert["safe_reach"]["responder_profile_id"]

    first_token = responder1["access_token"] if client.get("/responders/incidents", headers=auth(responder1["access_token"])).json() else responder2["access_token"]
    first_incidents = client.get("/responders/incidents", headers=auth(first_token)).json()
    assert first_incidents
    declined = client.post(f"/responders/incidents/{alert['id']}/decline", headers=auth(first_token))
    assert declined.status_code == 200, declined.text
    assert declined.json()["state"] == "declined"
    assert declined.json()["responder_profile_id"] == first_profile

    refreshed = client.get(f"/alerts/detail/{alert['id']}", headers=auth(owner["access_token"])).json()
    assert refreshed["safe_reach"] is not None
    assert refreshed["safe_reach"]["responder_profile_id"] != first_profile
    assert refreshed["safe_reach"]["state"] == "offered"


def test_35_unanswered_offer_expires_and_escalates_to_next_responder(tmp_path):
    cfg = Settings(
        database_path=str(tmp_path / "escalation.db"),
        jwt_secret="escalation-secret-0123456789-0123456789",
        admin_key="test-admin-key",
        proof_key_path=str(tmp_path / "proof.pem"),
        responder_offer_timeout_seconds=0,
    )
    with TestClient(create_app(database_path=cfg.database_path, settings=cfg)) as c:
        r1, _ = _verified_responder(c, email="first@example.com", lat=17.3851, lon=78.4868)
        r2, _ = _verified_responder(c, email="second@example.com", lat=17.3865, lon=78.4880)
        owner = register(c, "Asha", "asha@example.com")
        alert = _alert(c, owner, "safe-timeout-01").json()
        first_profile = alert["safe_reach"]["responder_profile_id"]
        heartbeat = c.post(
            f"/alerts/{alert['id']}/heartbeat",
            headers=auth(owner["access_token"]),
            json={"network_state": "mobile"},
        )
        assert heartbeat.status_code == 200, heartbeat.text
        second = heartbeat.json()["safe_reach"]
        assert second is not None
        assert second["responder_profile_id"] != first_profile
        proof = c.get(f"/alerts/{alert['id']}/proof", headers=auth(owner["access_token"])).json()
        types = [e["event_type"] for e in proof["events"]]
        assert "SAFE_REACH_OFFER_EXPIRED" in types


def test_36_phone_is_collected_and_disclosed_only_after_trusted_consent(client):
    owner = register(client, "Asha", "asha@example.com", phone_e164="+919876543210")
    contact = register(client, "Maya", "maya@example.com", phone_e164="+919812345678")
    invite = client.post(
        "/contacts/invite",
        headers=auth(owner["access_token"]),
        json={"email": "maya@example.com", "alias": "Sister"},
    )
    assert invite.status_code == 201
    assert invite.json()["contact_phone_e164"] is None
    accepted = client.post(
        "/contacts/accept",
        headers=auth(contact["access_token"]),
        json={"invite_token": invite.json()["invite_token"]},
    )
    assert accepted.status_code == 200
    contacts = client.get("/contacts", headers=auth(owner["access_token"])).json()
    assert contacts[0]["contact_phone_e164"] == "+919812345678"


def test_37_emergency_communication_actions_enter_signed_incident_record(client):
    owner, _, _ = _pair(client)
    alert = _alert(client, owner, "client-action-01").json()
    action = client.post(
        f"/alerts/{alert['id']}/client-actions",
        headers=auth(owner["access_token"]),
        json={
            "action": "sms_fallback_prepared",
            "metadata": {"contact_alias": "Sister", "latitude": 17.385, "longitude": 78.4867},
        },
    )
    assert action.status_code == 200, action.text
    proof = client.get(f"/alerts/{alert['id']}/proof", headers=auth(owner["access_token"])).json()
    assert any(e["event_type"] == "SMS_FALLBACK_PREPARED" for e in proof["events"])
    verified = client.get(f"/alerts/{alert['id']}/proof/verify", headers=auth(owner["access_token"])).json()
    assert verified["valid"] is True


def test_38_health_reports_resilient_commute_capabilities(client):
    health = client.get("/health")
    assert health.status_code == 200
    body = health.json()
    assert body["version"] == "1.6.0"
    assert body["sms_fallback"] == "system-composer"
    assert body["offline_journal"] == "sqlite"
