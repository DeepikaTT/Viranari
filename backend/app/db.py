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
    """Small, explicit SQLite migration layer for hackathon upgrades.

    It upgrades existing v1/v1.2 databases in-place so copying a new release to
    a VPS does not require deleting user/emergency data. Replace with Alembic
    before a real production launch with multiple database backends.
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
            return {c["name"] for c in inspect(engine).get_columns(table)}

        if "users" in tables and "phone_e164" not in columns("users"):
            conn.execute(text("ALTER TABLE users ADD COLUMN phone_e164 VARCHAR(16)"))

        if "alert_locations" in tables:
            cols = columns("alert_locations")
            if "speed_mps" not in cols:
                conn.execute(text("ALTER TABLE alert_locations ADD COLUMN speed_mps FLOAT"))
            cols = columns("alert_locations")
            if "heading_deg" not in cols:
                conn.execute(text("ALTER TABLE alert_locations ADD COLUMN heading_deg FLOAT"))

        now = datetime.now(timezone.utc).isoformat()
        conn.execute(
            text("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (13, :now)"),
            {"now": now},
        )


def build_session_factory(engine):
    return sessionmaker(bind=engine, class_=Session, expire_on_commit=False, future=True)
