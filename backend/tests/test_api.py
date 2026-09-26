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
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    conn.close()
    assert {"last_device_seen_at", "last_gps_fix_at", "last_location_sync_at"}.issubset(cols)


def test_33_silent_sos_roundtrips_and_reaches_inbox(client):
    owner, contact, _ = _pair(client)
    alert = client.post(
        "/alerts",
        headers=auth(owner["access_token"]),
        json={
            "idempotency_key": "silent-sos-0001",
            "latitude": 17.385,
            "longitude": 78.4867,
            "silent_mode": True,
            "note": "Silent Safety Session",
        },
    )
    assert alert.status_code == 201, alert.text
    assert alert.json()["silent_mode"] is True
    inbox = client.get("/alerts/inbox", headers=auth(contact["access_token"]))
    assert inbox.status_code == 200
    assert inbox.json()[0]["silent_mode"] is True


def test_34_presence_requires_mutual_participation_and_returns_no_identity(client):
    user = register(client, "Asha", "asha@example.com")
    headers = auth(user["access_token"])

    # Device A cannot passively observe until it participates.
    before = client.get(
        "/presence/nearby?device_id=device-a-12345678&latitude=17.385&longitude=78.4867&radius_m=2000",
        headers=headers,
    )
    assert before.status_code == 200
    assert before.json() == []

    for device_id, lat, lon in [
        ("device-a-12345678", 17.3850, 78.4867),
        ("device-b-12345678", 17.3860, 78.4877),
    ]:
        r = client.post(
            "/presence",
            headers=headers,
            json={"device_id": device_id, "latitude": lat, "longitude": lon, "enabled": True},
        )
        assert r.status_code == 200, r.text

    nearby = client.get(
        "/presence/nearby?device_id=device-a-12345678&latitude=17.385&longitude=78.4867&radius_m=2000",
        headers=headers,
    )
    assert nearby.status_code == 200, nearby.text
    assert len(nearby.json()) == 1
    point = nearby.json()[0]
    assert set(point) == {"approx_distance_m", "bearing_deg", "age_seconds"}
    assert "device_id" not in point
    assert "owner_user_id" not in point


def test_35_safe_nodes_only_expose_verified_active_places(client):
    from app.models import SafeNode

    user = register(client, "Asha", "asha@example.com")
    with client.app.state.SessionLocal() as db:
        db.add_all(
            [
                SafeNode(
                    name="Verified Campus Gate",
                    category="campus_security",
                    latitude=17.386,
                    longitude=78.487,
                    verified=True,
                    active=True,
                ),
                SafeNode(
                    name="Unverified Shop",
                    category="staffed_place",
                    latitude=17.3855,
                    longitude=78.487,
                    verified=False,
                    active=True,
                ),
                SafeNode(
                    name="Disabled Node",
                    category="hospital",
                    latitude=17.3852,
                    longitude=78.487,
                    verified=True,
                    active=False,
                ),
            ]
        )
        db.commit()

    r = client.get(
        "/safe-nodes/nearby?latitude=17.385&longitude=78.4867&radius_m=5000",
        headers=auth(user["access_token"]),
    )
    assert r.status_code == 200, r.text
    rows = r.json()
    assert [row["name"] for row in rows] == ["Verified Campus Gate"]
    assert rows[0]["verified"] is True
    assert rows[0]["approx_distance_m"] > 0


def test_36_existing_alert_schema_gains_silent_mode(tmp_path):
    import sqlite3
    from app.db import apply_compat_migrations, build_engine

    db_path = tmp_path / "pre-v15.db"
    conn = sqlite3.connect(db_path)
    conn.executescript(
        """
        CREATE TABLE alerts (
            id VARCHAR(36) PRIMARY KEY,
            owner_id VARCHAR(36), idempotency_key VARCHAR(100),
            latitude FLOAT, longitude FLOAT, accuracy_m FLOAT,
            battery_percent INTEGER, network_state VARCHAR(40), is_test BOOLEAN,
            note TEXT, state VARCHAR(20), created_at DATETIME, updated_at DATETIME,
            cancelled_at DATETIME, resolved_at DATETIME,
            last_device_seen_at DATETIME, last_gps_fix_at DATETIME, last_location_sync_at DATETIME
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
    value = conn.execute("SELECT silent_mode FROM alerts WHERE id='a1'").fetchone()[0]
    conn.close()
    assert "silent_mode" in cols
    assert value == 0


def test_37_responder_location_requires_acknowledgement(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "responder-no-ack-01").json()
    r = client.post(
        f"/alerts/{alert['id']}/responder-location",
        headers=auth(contact["access_token"]),
        json={"latitude": 17.390, "longitude": 78.490, "accuracy_m": 5.0},
    )
    assert r.status_code == 409


def test_38_acknowledged_responder_shares_distance_and_eta_with_victim(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "responder-live-01").json()
    ack = client.post(f"/alerts/{alert['id']}/acknowledge", headers=auth(contact["access_token"]))
    assert ack.status_code == 200
    update = client.post(
        f"/alerts/{alert['id']}/responder-location",
        headers=auth(contact["access_token"]),
        json={
            "latitude": 17.390,
            "longitude": 78.490,
            "accuracy_m": 5.0,
            "speed_mps": 2.0,
            "heading_deg": 45.0,
        },
    )
    assert update.status_code == 200, update.text
    row = update.json()
    assert row["distance_m"] > 0
    assert row["eta_seconds"] > 0
    assert row["responder_name"] == "Maya"

    victim_view = client.get(
        f"/alerts/{alert['id']}/responders",
        headers=auth(owner["access_token"]),
    )
    assert victim_view.status_code == 200
    assert len(victim_view.json()) == 1
    assert victim_view.json()[0]["responder_user_id"] == row["responder_user_id"]


def test_39_responder_view_does_not_expose_other_responder_locations(client):
    owner = register(client, "Asha", "asha@example.com")
    maya = register(client, "Maya", "maya@example.com")
    riya = register(client, "Riya", "riya@example.com")
    for contact, email in [(maya, "maya@example.com"), (riya, "riya@example.com")]:
        invite = client.post(
            "/contacts/invite",
            headers=auth(owner["access_token"]),
            json={"email": email, "alias": "Trusted"},
        ).json()
        client.post(
            "/contacts/accept",
            headers=auth(contact["access_token"]),
            json={"invite_token": invite["invite_token"]},
        )
    alert = _alert(client, owner, "responder-privacy-01").json()
    for contact, lat in [(maya, 17.390), (riya, 17.395)]:
        client.post(f"/alerts/{alert['id']}/acknowledge", headers=auth(contact["access_token"]))
        client.post(
            f"/alerts/{alert['id']}/responder-location",
            headers=auth(contact["access_token"]),
            json={"latitude": lat, "longitude": 78.490},
        )
    maya_view = client.get(
        f"/alerts/{alert['id']}/responders",
        headers=auth(maya["access_token"]),
    )
    assert maya_view.status_code == 200
    assert len(maya_view.json()) == 1
    assert maya_view.json()[0]["responder_name"] == "Maya"


def test_40_presence_radius_filters_500m_2km_5km(client):
    user = register(client, "Asha", "asha@example.com")
    headers = auth(user["access_token"])
    points = [
        ("device-a-radius-0001", 17.3850, 78.4867),
        ("device-b-radius-0001", 17.3880, 78.4867),
        ("device-c-radius-0001", 17.3990, 78.4867),
        ("device-d-radius-0001", 17.4240, 78.4867),
    ]
    for device_id, lat, lon in points:
        r = client.post(
            "/presence",
            headers=headers,
            json={"device_id": device_id, "latitude": lat, "longitude": lon, "enabled": True},
        )
        assert r.status_code == 200

    def count(radius):
        r = client.get(
            f"/presence/nearby?device_id=device-a-radius-0001&latitude=17.385&longitude=78.4867&radius_m={radius}",
            headers=headers,
        )
        assert r.status_code == 200
        return len(r.json())

    assert count(500) == 1
    assert count(2000) == 2
    assert count(5000) == 3


def test_41_responder_trail_records_movement(client):
    owner, contact, _ = _pair(client)
    alert = _alert(client, owner, "responder-trail-01").json()
    client.post(f"/alerts/{alert['id']}/acknowledge", headers=auth(contact["access_token"]))

    for lat, lon in [(17.3900, 78.4900), (17.3902, 78.4902)]:
        r = client.post(
            f"/alerts/{alert['id']}/responder-location",
            headers=auth(contact["access_token"]),
            json={"latitude": lat, "longitude": lon, "accuracy_m": 5.0},
        )
        assert r.status_code == 200, r.text

    trail = client.get(
        f"/alerts/{alert['id']}/responder-locations",
        headers=auth(contact["access_token"]),
    )
    assert trail.status_code == 200, trail.text
    points = trail.json()
    assert len(points) >= 2
    assert points[-1]["latitude"] == 17.3902

    victim_trail = client.get(
        f"/alerts/{alert['id']}/responder-locations",
        headers=auth(owner["access_token"]),
    )
    assert victim_trail.status_code == 200
    assert len(victim_trail.json()) >= 2
