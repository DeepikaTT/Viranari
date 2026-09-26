from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker


class Base(DeclarativeBase):
    pass


def build_engine(database_path: str):
    Path(database_path).parent.mkdir(parents=True, exist_ok=True)
    engine = create_engine(
        f"sqlite:///{database_path}",
        connect_args={"check_same_thread": False},
        future=True,
    )

    @event.listens_for(engine, "connect")
    def _sqlite_pragmas(dbapi_connection, _):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.close()

    return engine


def apply_compat_migrations(engine) -> None:
    """Idempotent SQLite compatibility migrations for ViraNari upgrades.

    This deliberately inspects the live schema on every startup instead of
    trusting a migration-version marker. Early V1.3 builds could record the
    migration marker without adding all V1.2 Alert columns, so schema presence
    is the source of truth here. Replace with Alembic before production scale.
    """
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    if not tables:
        return

    with engine.begin() as conn:
        conn.execute(text(
            "CREATE TABLE IF NOT EXISTS schema_migrations "
            "(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)"
        ))

        def columns(table: str) -> set[str]:
            # Use PRAGMA through the current connection so newly added columns
            # are visible immediately and no Inspector cache can go stale.
            rows = conn.execute(text(f"PRAGMA table_info({table})")).fetchall()
            return {row[1] for row in rows}

        # V1.3 contact/SMS field.
        if "users" in tables and "phone_e164" not in columns("users"):
            conn.execute(text("ALTER TABLE users ADD COLUMN phone_e164 VARCHAR(16)"))

        # V1.5 role-based responder access. Existing users remain travelers.
        if "users" in tables:
            user_cols = columns("users")
            if "role" not in user_cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN role VARCHAR(24) NOT NULL DEFAULT 'traveler'"))
            conn.execute(text("UPDATE users SET role = 'traveler' WHERE role IS NULL OR role = ''"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_users_role ON users (role)"))

        # V1 -> V1.2 alert-session fields. Older databases may have only the
        # one-shot SOS columns, and SQLAlchemy create_all() does not ALTER them.
        if "alerts" in tables:
            alert_cols = columns("alerts")
            alert_additions = [
                ("network_state", "VARCHAR(40)"),
                ("is_test", "BOOLEAN NOT NULL DEFAULT 0"),
                ("state", "VARCHAR(20) NOT NULL DEFAULT 'active'"),
                ("updated_at", "DATETIME"),
                ("cancelled_at", "DATETIME"),
                ("resolved_at", "DATETIME"),
            ]
            for name, sql_type in alert_additions:
                if name not in alert_cols:
                    conn.execute(text(f"ALTER TABLE alerts ADD COLUMN {name} {sql_type}"))
                    alert_cols.add(name)

            # Preserve the semantics of old records while making them valid for
            # the V1.2/V1.3 session model.
            conn.execute(text("UPDATE alerts SET is_test = 0 WHERE is_test IS NULL"))
            conn.execute(text(
                "UPDATE alerts SET state = CASE "
                "WHEN cancelled_at IS NOT NULL THEN 'cancelled' ELSE 'active' END "
                "WHERE state IS NULL OR state = ''"
            ))
            conn.execute(text(
                "UPDATE alerts SET updated_at = COALESCE(updated_at, created_at) "
                "WHERE updated_at IS NULL"
            ))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_alerts_state ON alerts (state)"))

        # V1.3 movement fields. Base.metadata.create_all() creates the full table
        # when it is absent; this path upgrades an existing V1.2 table.
        if "alert_locations" in tables:
            loc_cols = columns("alert_locations")
            if "speed_mps" not in loc_cols:
                conn.execute(text("ALTER TABLE alert_locations ADD COLUMN speed_mps FLOAT"))
                loc_cols.add("speed_mps")
            if "heading_deg" not in loc_cols:
                conn.execute(text("ALTER TABLE alert_locations ADD COLUMN heading_deg FLOAT"))

        # V1.4 liveness timestamps. These deliberately do not reuse updated_at:
        # updated_at can change for reasons other than device liveness.
        if "alerts" in tables:
            alert_cols = columns("alerts")
            heartbeat_additions = [
                ("last_device_seen_at", "DATETIME"),
                ("last_gps_fix_at", "DATETIME"),
                ("last_location_sync_at", "DATETIME"),
            ]
            for name, sql_type in heartbeat_additions:
                if name not in alert_cols:
                    conn.execute(text(f"ALTER TABLE alerts ADD COLUMN {name} {sql_type}"))
                    alert_cols.add(name)
            conn.execute(text(
                "UPDATE alerts SET "
                "last_device_seen_at = COALESCE(last_device_seen_at, updated_at, created_at), "
                "last_gps_fix_at = COALESCE(last_gps_fix_at, updated_at, created_at), "
                "last_location_sync_at = COALESCE(last_location_sync_at, updated_at, created_at) "
                "WHERE last_device_seen_at IS NULL OR last_gps_fix_at IS NULL OR last_location_sync_at IS NULL"
            ))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_alerts_last_device_seen_at ON alerts (last_device_seen_at)"))

        now = datetime.now(timezone.utc).isoformat()
        conn.execute(
            text("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (150, :now)"),
            {"now": now},
        )


def build_session_factory(engine):
    return sessionmaker(bind=engine, class_=Session, expire_on_commit=False, future=True)
