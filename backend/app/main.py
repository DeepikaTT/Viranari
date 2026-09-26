from __future__ import annotations

import logging
import math
import secrets
from collections import defaultdict, deque
from threading import Lock
from time import monotonic
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import and_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from .config import Settings, settings as default_settings
from .db import Base, apply_compat_migrations, build_engine, build_session_factory
from .models import (
    Alert,
    AlertLocation,
    AuditEvent,
    AlertRecipient,
    AlertState,
    ContactStatus,
    SafeNode,
    ResponderLocation,
    ResponderLocationPoint,
    SafetyPresenceDevice,
    TrustedContact,
    User,
    utcnow,
)
from .schemas import (
    AlertCreateIn,
    AlertLocationIn,
    AlertLocationBatchIn,
    AlertHeartbeatIn,
    AlertLocationBatchOut,
    AlertLocationOut,
    AlertOut,
    AuditEventOut,
    ContactAcceptIn,
    ContactCreateIn,
    ContactOut,
    InboxAlertOut,
    LoginIn,
    MessageOut,
    PhoneUpdateIn,
    PresencePointOut,
    PresenceUpdateIn,
    RecipientStatusOut,
    ResponderLocationIn,
    ResponderStateOut,
    ResponderTrailPointOut,
    SafeNodeOut,
    RegisterIn,
    TokenOut,
    UserOut,
)
from .security import create_access_token, decode_access_token, hash_password, verify_password

bearer = HTTPBearer(auto_error=False)
logger = logging.getLogger("viranari")


class SlidingWindowLimiter:
    def __init__(self):
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def allow(self, key: str, *, limit: int, window_seconds: int) -> bool:
        now = monotonic()
        cutoff = now - window_seconds
        with self._lock:
            q = self._events[key]
            while q and q[0] < cutoff:
                q.popleft()
            if len(q) >= limit:
                return False
            q.append(now)
            return True



def create_app(*, database_path: str | None = None, settings: Settings | None = None) -> FastAPI:
    cfg = settings or default_settings
    db_path = database_path or cfg.database_path
    engine = build_engine(db_path)
    SessionLocal = build_session_factory(engine)
    # Upgrade existing SQLite tables before SQLAlchemy tries to create indexes
    # for new model columns. Then create any entirely new V1.4 tables.
    apply_compat_migrations(engine)
    Base.metadata.create_all(engine)

    app = FastAPI(
        title="ViraNari API",
        version="1.8.6",
        description=(
            "Emergency-response API with consent-based trusted contacts, delivery receipts, "
            "idempotent offline retry, heartbeat-based live safety, silent safety sessions, "
            "anonymous Safety Map presence, responder-to-victim live distance/ETA, incoming SOS coordination, "
            "and verified Safe Node compass support."
        ),
    )
    app.state.engine = engine
    app.state.SessionLocal = SessionLocal
    app.state.settings = cfg
    limiter = SlidingWindowLimiter()

    app.add_middleware(
        CORSMiddleware,
        allow_origins=[o.strip() for o in cfg.cors_origins.split(",")] if cfg.cors_origins != "*" else ["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    def get_db():
        db = SessionLocal()
        try:
            yield db
        finally:
            db.close()

    def get_current_user(
        credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
        db: Session = Depends(get_db),
    ) -> User:
        if not credentials:
            raise HTTPException(status_code=401, detail="Missing bearer token")
        try:
            user_id = decode_access_token(credentials.credentials, cfg)
        except jwt.PyJWTError:
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        user = db.get(User, user_id)
        if not user:
            raise HTTPException(status_code=401, detail="User no longer exists")
        return user

    def ensure_utc(value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    def user_out(user: User) -> UserOut:
        return UserOut(id=user.id, name=user.name, email=user.email, phone_e164=user.phone_e164)

    def contact_out(db: Session, contact: TrustedContact, include_token: bool = False) -> ContactOut:
        target = db.get(User, contact.contact_user_id)
        return ContactOut(
            id=contact.id,
            contact_user_id=contact.contact_user_id,
            contact_name=target.name,
            contact_email=target.email,
            # Phone numbers are disclosed only after the contact explicitly accepts.
            contact_phone_e164=target.phone_e164 if contact.status == ContactStatus.active.value else None,
            alias=contact.alias,
            status=contact.status,
            invite_token=contact.invite_token if include_token and contact.status == ContactStatus.pending.value else None,
            invite_expires_at=ensure_utc(contact.invite_expires_at),
            accepted_at=ensure_utc(contact.accepted_at),
        )

    def alert_query():
        return select(Alert).options(joinedload(Alert.recipients), joinedload(Alert.locations))

    def can_view_alert(alert: Alert, user_id: str) -> bool:
        if alert.owner_id == user_id:
            return True
        return any(r.recipient_user_id == user_id and r.is_active for r in alert.recipients)

    def audit(db: Session, event_type: str, actor_user_id: str | None, resource_id: str | None = None, detail: str | None = None) -> None:
        db.add(AuditEvent(actor_user_id=actor_user_id, event_type=event_type, resource_id=resource_id, detail=detail))

    def enforce_rate(key: str, *, limit: int, window_seconds: int = 60) -> None:
        if not limiter.allow(key, limit=limit, window_seconds=window_seconds):
            raise HTTPException(status_code=429, detail="Too many requests. Try again shortly.")

    def alert_out(db: Session, alert: Alert) -> AlertOut:
        owner = db.get(User, alert.owner_id)
        recipients: list[RecipientStatusOut] = []
        for r in alert.recipients:
            recipient = db.get(User, r.recipient_user_id)
            recipients.append(
                RecipientStatusOut(
                    recipient_user_id=r.recipient_user_id,
                    recipient_name=recipient.name,
                    delivered_at=ensure_utc(r.delivered_at),
                    acknowledged_at=ensure_utc(r.acknowledged_at),
                )
            )
        return AlertOut(
            id=alert.id,
            owner_id=alert.owner_id,
            owner_name=owner.name,
            idempotency_key=alert.idempotency_key,
            latitude=alert.latitude,
            longitude=alert.longitude,
            accuracy_m=alert.accuracy_m,
            battery_percent=alert.battery_percent,
            network_state=alert.network_state,
            is_test=alert.is_test,
            silent_mode=alert.silent_mode,
            note=alert.note,
            state=alert.state,
            created_at=ensure_utc(alert.created_at),
            updated_at=ensure_utc(alert.updated_at),
            cancelled_at=ensure_utc(alert.cancelled_at),
            resolved_at=ensure_utc(alert.resolved_at),
            last_device_seen_at=ensure_utc(alert.last_device_seen_at),
            last_gps_fix_at=ensure_utc(alert.last_gps_fix_at),
            last_location_sync_at=ensure_utc(alert.last_location_sync_at),
            recipients=recipients,
        )

    @app.get("/health")
    def health():
        return {"status": "ok", "service": "viranari-api", "version": "1.8.6"}

    @app.post("/auth/register", response_model=TokenOut, status_code=201)
    def register(payload: RegisterIn, db: Session = Depends(get_db)):
        email = payload.email.lower().strip()
        user = User(name=payload.name.strip(), email=email, phone_e164=payload.phone_e164, password_hash=hash_password(payload.password))
        db.add(user)
        try:
            db.flush()
            audit(db, "account_registered", user.id, user.id, user.email)
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=409, detail="Email already registered")
        db.refresh(user)
        return TokenOut(access_token=create_access_token(user.id, cfg), user=user_out(user))

    @app.post("/auth/login", response_model=TokenOut)
    def login(payload: LoginIn, db: Session = Depends(get_db)):
        user = db.scalar(select(User).where(User.email == payload.email.lower().strip()))
        if not user or not verify_password(payload.password, user.password_hash):
            raise HTTPException(status_code=401, detail="Invalid email or password")
        return TokenOut(access_token=create_access_token(user.id, cfg), user=user_out(user))

    @app.get("/me", response_model=UserOut)
    def me(current: User = Depends(get_current_user)):
        return user_out(current)

    @app.patch("/me/phone", response_model=UserOut)
    def update_phone(
        payload: PhoneUpdateIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        current.phone_e164 = payload.phone_e164
        audit(db, "phone_updated", current.id, current.id, "Trusted contact phone number updated")
        db.commit()
        db.refresh(current)
        return user_out(current)

    @app.get("/contacts", response_model=list[ContactOut])
    def list_contacts(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        contacts = db.scalars(
            select(TrustedContact)
            .where(TrustedContact.owner_id == current.id)
            .order_by(TrustedContact.created_at.desc())
        ).all()
        return [contact_out(db, c, include_token=True) for c in contacts]

    @app.post("/contacts/invite", response_model=ContactOut, status_code=201)
    def invite_contact(
        payload: ContactCreateIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        target = db.scalar(select(User).where(User.email == payload.email.lower().strip()))
        if not target:
            raise HTTPException(status_code=404, detail="Trusted contact must register first")
        if target.id == current.id:
            raise HTTPException(status_code=400, detail="You cannot add yourself")

        existing = db.scalar(
            select(TrustedContact).where(
                and_(TrustedContact.owner_id == current.id, TrustedContact.contact_user_id == target.id)
            )
        )
        now = utcnow()
        token = secrets.token_urlsafe(12)
        expiry = now + timedelta(minutes=cfg.invite_minutes)

        if existing:
            if existing.status == ContactStatus.active.value:
                raise HTTPException(status_code=409, detail="Already an active trusted contact")
            existing.alias = payload.alias.strip() or "Trusted contact"
            existing.status = ContactStatus.pending.value
            existing.invite_token = token
            existing.invite_expires_at = expiry
            existing.removed_at = None
            existing.accepted_at = None
            contact = existing
        else:
            contact = TrustedContact(
                owner_id=current.id,
                contact_user_id=target.id,
                alias=payload.alias.strip() or "Trusted contact",
                status=ContactStatus.pending.value,
                invite_token=token,
                invite_expires_at=expiry,
            )
            db.add(contact)
        audit(db, "trusted_contact_invited", current.id, contact.id, target.email)
        db.commit()
        db.refresh(contact)
        return contact_out(db, contact, include_token=True)

    @app.post("/contacts/accept", response_model=ContactOut)
    def accept_contact(
        payload: ContactAcceptIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        contact = db.scalar(select(TrustedContact).where(TrustedContact.invite_token == payload.invite_token))
        if not contact or contact.contact_user_id != current.id:
            raise HTTPException(status_code=404, detail="Invite not found")
        expiry = contact.invite_expires_at
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=timezone.utc)
        if expiry < datetime.now(timezone.utc):
            raise HTTPException(status_code=410, detail="Invite expired")
        if contact.status == ContactStatus.removed.value:
            raise HTTPException(status_code=410, detail="Invite was revoked")
        contact.status = ContactStatus.active.value
        contact.accepted_at = utcnow()
        audit(db, "trusted_contact_accepted", current.id, contact.id, None)
        db.commit()
        db.refresh(contact)
        return contact_out(db, contact)

    @app.delete("/contacts/{contact_id}", response_model=MessageOut)
    def remove_contact(
        contact_id: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        contact = db.get(TrustedContact, contact_id)
        if not contact or contact.owner_id != current.id:
            raise HTTPException(status_code=404, detail="Contact not found")
        contact.status = ContactStatus.removed.value
        contact.removed_at = utcnow()
        audit(db, "trusted_contact_removed", current.id, contact.id, None)
        db.commit()
        return MessageOut(message="Trusted contact removed")

    @app.post("/alerts", response_model=AlertOut, status_code=201)
    def create_alert(
        payload: AlertCreateIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        enforce_rate(f"alert:{current.id}", limit=8)
        existing = db.scalar(select(Alert).where(Alert.idempotency_key == payload.idempotency_key))
        if existing:
            if existing.owner_id != current.id:
                raise HTTPException(status_code=409, detail="Idempotency key already in use")
            existing = db.scalar(alert_query().where(Alert.id == existing.id))
            return alert_out(db, existing)

        now = utcnow()
        alert = Alert(
            owner_id=current.id,
            idempotency_key=payload.idempotency_key,
            latitude=payload.latitude,
            longitude=payload.longitude,
            accuracy_m=payload.accuracy_m,
            battery_percent=payload.battery_percent,
            network_state=payload.network_state,
            is_test=payload.is_test,
            silent_mode=payload.silent_mode,
            note=payload.note,
            state=AlertState.active.value,
            updated_at=now,
            last_device_seen_at=now,
            last_gps_fix_at=now,
            last_location_sync_at=now,
        )
        db.add(alert)
        db.flush()
        db.add(
            AlertLocation(
                alert_id=alert.id,
                latitude=payload.latitude,
                longitude=payload.longitude,
                accuracy_m=payload.accuracy_m,
                battery_percent=payload.battery_percent,
                network_state=payload.network_state,
                speed_mps=payload.speed_mps,
                heading_deg=payload.heading_deg,
                recorded_at=now,
            )
        )

        active_contacts = db.scalars(
            select(TrustedContact).where(
                and_(
                    TrustedContact.owner_id == current.id,
                    TrustedContact.status == ContactStatus.active.value,
                )
            )
        ).all()
        for c in active_contacts:
            db.add(AlertRecipient(alert_id=alert.id, recipient_user_id=c.contact_user_id))

        event_type = "silent_sos_created" if payload.silent_mode else ("sos_created_test" if payload.is_test else "sos_created")
        audit(db, event_type, current.id, alert.id, f"recipients={len(active_contacts)}")
        logger.info("sos_created user=%s alert=%s recipients=%s test=%s silent=%s", current.id, alert.id, len(active_contacts), payload.is_test, payload.silent_mode)
        db.commit()
        result = db.scalar(alert_query().where(Alert.id == alert.id))
        return alert_out(db, result)

    @app.get("/alerts/active", response_model=AlertOut)
    def active_alert(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        alert = db.scalar(
            alert_query()
            .where(and_(Alert.owner_id == current.id, Alert.state == AlertState.active.value))
            .order_by(Alert.created_at.desc())
        )
        if not alert:
            raise HTTPException(status_code=404, detail="No active alert")
        return alert_out(db, alert)

    @app.get("/alerts/by-idempotency/{key}", response_model=AlertOut)
    def alert_by_idempotency(
        key: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        alert = db.scalar(alert_query().where(Alert.idempotency_key == key))
        if not alert or alert.owner_id != current.id:
            raise HTTPException(status_code=404, detail="Alert not found")
        return alert_out(db, alert)

    @app.get("/alerts/history", response_model=list[AlertOut])
    def alert_history(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        alerts = db.scalars(
            alert_query()
            .where(Alert.owner_id == current.id)
            .order_by(Alert.created_at.desc())
        ).unique().all()
        return [alert_out(db, a) for a in alerts]

    @app.get("/alerts/detail/{alert_id}", response_model=AlertOut)
    def get_alert(
        alert_id: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert:
            raise HTTPException(status_code=404, detail="Alert not found")
        if not can_view_alert(alert, current.id):
            raise HTTPException(status_code=403, detail="Not allowed to view this alert")
        return alert_out(db, alert)

    @app.post("/alerts/{alert_id}/location", response_model=AlertOut)
    def update_alert_location(
        alert_id: str,
        payload: AlertLocationIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        enforce_rate(f"location:{current.id}", limit=120)
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert or alert.owner_id != current.id:
            raise HTTPException(status_code=404, detail="Alert not found")
        if alert.state != AlertState.active.value:
            raise HTTPException(status_code=409, detail="Emergency session is not active")

        now = utcnow()
        alert.latitude = payload.latitude
        alert.longitude = payload.longitude
        alert.accuracy_m = payload.accuracy_m
        alert.battery_percent = payload.battery_percent
        alert.network_state = payload.network_state
        alert.updated_at = now
        alert.last_device_seen_at = now
        alert.last_gps_fix_at = now
        alert.last_location_sync_at = now
        db.add(
            AlertLocation(
                alert_id=alert.id,
                latitude=payload.latitude,
                longitude=payload.longitude,
                accuracy_m=payload.accuracy_m,
                battery_percent=payload.battery_percent,
                network_state=payload.network_state,
                speed_mps=payload.speed_mps,
                heading_deg=payload.heading_deg,
                recorded_at=now,
            )
        )
        db.commit()
        result = db.scalar(alert_query().where(Alert.id == alert.id))
        return alert_out(db, result)

    @app.post("/alerts/{alert_id}/locations/batch", response_model=AlertLocationBatchOut)
    def update_alert_locations_batch(
        alert_id: str,
        payload: AlertLocationBatchIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        enforce_rate(f"location-batch:{current.id}", limit=30)
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert or alert.owner_id != current.id:
            raise HTTPException(status_code=404, detail="Alert not found")
        if alert.state != AlertState.active.value:
            raise HTTPException(status_code=409, detail="Emergency session is not active")

        now = utcnow()
        alert_created = ensure_utc(alert.created_at)
        accepted = 0
        latest_payload = None
        latest_recorded = None
        for point in payload.points:
            recorded = ensure_utc(point.recorded_at)
            if recorded > now + timedelta(minutes=5):
                recorded = now
            if recorded < alert_created - timedelta(minutes=1):
                recorded = alert_created
            db.add(
                AlertLocation(
                    alert_id=alert.id,
                    latitude=point.latitude,
                    longitude=point.longitude,
                    accuracy_m=point.accuracy_m,
                    battery_percent=point.battery_percent,
                    network_state=point.network_state,
                    speed_mps=point.speed_mps,
                    heading_deg=point.heading_deg,
                    recorded_at=recorded,
                )
            )
            accepted += 1
            if latest_recorded is None or recorded >= latest_recorded:
                latest_recorded = recorded
                latest_payload = point

        if latest_payload is not None:
            alert.latitude = latest_payload.latitude
            alert.longitude = latest_payload.longitude
            alert.accuracy_m = latest_payload.accuracy_m
            alert.battery_percent = latest_payload.battery_percent
            alert.network_state = latest_payload.network_state
            alert.updated_at = now
            alert.last_device_seen_at = now
            alert.last_gps_fix_at = latest_recorded
            alert.last_location_sync_at = now

        db.commit()
        return AlertLocationBatchOut(accepted=accepted)

    @app.post("/alerts/{alert_id}/heartbeat", response_model=AlertOut)
    def alert_heartbeat(
        alert_id: str,
        payload: AlertHeartbeatIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        enforce_rate(f"heartbeat:{current.id}", limit=120)
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert or alert.owner_id != current.id:
            raise HTTPException(status_code=404, detail="Alert not found")
        if alert.state != AlertState.active.value:
            raise HTTPException(status_code=409, detail="Emergency session is not active")

        now = utcnow()
        alert.last_device_seen_at = now
        alert.updated_at = now
        if payload.battery_percent is not None:
            alert.battery_percent = payload.battery_percent
        if payload.network_state is not None:
            alert.network_state = payload.network_state
        if payload.last_gps_fix_at is not None:
            gps_time = ensure_utc(payload.last_gps_fix_at)
            if gps_time <= now + timedelta(minutes=5):
                alert.last_gps_fix_at = gps_time
        db.commit()
        result = db.scalar(alert_query().where(Alert.id == alert.id))
        return alert_out(db, result)

    @app.get("/alerts/{alert_id}/locations", response_model=list[AlertLocationOut])
    def alert_locations(
        alert_id: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert:
            raise HTTPException(status_code=404, detail="Alert not found")
        if not can_view_alert(alert, current.id):
            raise HTTPException(status_code=403, detail="Not allowed to view this alert")
        locations = db.scalars(
            select(AlertLocation)
            .where(AlertLocation.alert_id == alert_id)
            .order_by(AlertLocation.recorded_at.asc())
        ).all()
        return [
            AlertLocationOut(
                latitude=p.latitude,
                longitude=p.longitude,
                accuracy_m=p.accuracy_m,
                battery_percent=p.battery_percent,
                network_state=p.network_state,
                speed_mps=p.speed_mps,
                heading_deg=p.heading_deg,
                recorded_at=ensure_utc(p.recorded_at),
            )
            for p in locations
        ]

    def close_alert(alert_id: str, target_state: AlertState, current: User, db: Session) -> AlertOut:
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert or alert.owner_id != current.id:
            raise HTTPException(status_code=404, detail="Alert not found")
        if alert.state != AlertState.active.value:
            return alert_out(db, alert)
        now = utcnow()
        alert.state = target_state.value
        alert.updated_at = now
        if target_state is AlertState.cancelled:
            alert.cancelled_at = now
        else:
            alert.resolved_at = now
        audit(db, f"sos_{target_state.value}", current.id, alert.id, None)
        logger.info("sos_%s user=%s alert=%s", target_state.value, current.id, alert.id)
        db.commit()
        result = db.scalar(alert_query().where(Alert.id == alert.id))
        return alert_out(db, result)

    @app.post("/alerts/{alert_id}/cancel", response_model=AlertOut)
    def cancel_alert(
        alert_id: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        return close_alert(alert_id, AlertState.cancelled, current, db)

    @app.post("/alerts/{alert_id}/resolve", response_model=AlertOut)
    def resolve_alert(
        alert_id: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        return close_alert(alert_id, AlertState.resolved, current, db)

    @app.get("/alerts/inbox", response_model=list[InboxAlertOut])
    def inbox(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        rows = db.execute(
            select(AlertRecipient, Alert, User)
            .join(Alert, AlertRecipient.alert_id == Alert.id)
            .join(User, Alert.owner_id == User.id)
            .where(and_(AlertRecipient.recipient_user_id == current.id, AlertRecipient.is_active.is_(True)))
            .order_by(Alert.created_at.desc())
        ).all()
        now = utcnow()
        changed = False
        out: list[InboxAlertOut] = []
        for recipient, alert, sender in rows:
            if recipient.delivered_at is None:
                recipient.delivered_at = now
                changed = True
            out.append(
                InboxAlertOut(
                    alert_id=alert.id,
                    sender_name=sender.name,
                    sender_email=sender.email,
                    sender_phone_e164=sender.phone_e164,
                    latitude=alert.latitude,
                    longitude=alert.longitude,
                    accuracy_m=alert.accuracy_m,
                    battery_percent=alert.battery_percent,
                    network_state=alert.network_state,
                    is_test=alert.is_test,
                    silent_mode=alert.silent_mode,
                    state=alert.state,
                    note=alert.note,
                    created_at=ensure_utc(alert.created_at),
                    updated_at=ensure_utc(alert.updated_at),
                    delivered_at=ensure_utc(recipient.delivered_at),
                    acknowledged_at=ensure_utc(recipient.acknowledged_at),
                    last_device_seen_at=ensure_utc(alert.last_device_seen_at),
                    last_gps_fix_at=ensure_utc(alert.last_gps_fix_at),
                    last_location_sync_at=ensure_utc(alert.last_location_sync_at),
                )
            )
        if changed:
            db.commit()
        return out

    @app.post("/alerts/{alert_id}/acknowledge", response_model=MessageOut)
    def acknowledge(
        alert_id: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        recipient = db.scalar(
            select(AlertRecipient).where(
                and_(
                    AlertRecipient.alert_id == alert_id,
                    AlertRecipient.recipient_user_id == current.id,
                    AlertRecipient.is_active.is_(True),
                )
            )
        )
        if not recipient:
            raise HTTPException(status_code=404, detail="Alert not found in your inbox")
        if recipient.delivered_at is None:
            recipient.delivered_at = utcnow()
        if recipient.acknowledged_at is None:
            recipient.acknowledged_at = utcnow()
        audit(db, "sos_acknowledged", current.id, alert_id, None)
        db.commit()
        return MessageOut(message="Alert acknowledged")


    # ---------- V1.8 trusted responder live location ----------
    def _responder_state(db: Session, alert: Alert, row: ResponderLocation) -> ResponderStateOut:
        responder = db.get(User, row.responder_user_id)
        distance, _ = _distance_and_bearing(alert.latitude, alert.longitude, row.latitude, row.longitude)
        # Approximate ETA only: use current measured responder speed when useful,
        # otherwise a conservative walking pace. The UI labels this as approximate.
        pace_mps = row.speed_mps if row.speed_mps is not None and row.speed_mps >= 0.8 else 1.4
        eta_seconds = max(0, int(round(distance / max(0.8, pace_mps))))
        return ResponderStateOut(
            responder_user_id=row.responder_user_id,
            responder_name=responder.name if responder else "Trusted responder",
            latitude=row.latitude,
            longitude=row.longitude,
            accuracy_m=row.accuracy_m,
            speed_mps=row.speed_mps,
            heading_deg=row.heading_deg,
            updated_at=ensure_utc(row.updated_at),
            distance_m=max(0, int(round(distance))),
            eta_seconds=eta_seconds,
        )

    @app.post("/alerts/{alert_id}/responder-location", response_model=ResponderStateOut)
    def update_responder_location(
        alert_id: str,
        payload: ResponderLocationIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert:
            raise HTTPException(status_code=404, detail="Alert not found")
        if alert.state != AlertState.active.value:
            raise HTTPException(status_code=409, detail="Emergency is no longer active")
        recipient = db.scalar(
            select(AlertRecipient).where(
                and_(
                    AlertRecipient.alert_id == alert_id,
                    AlertRecipient.recipient_user_id == current.id,
                    AlertRecipient.is_active.is_(True),
                )
            )
        )
        if not recipient:
            raise HTTPException(status_code=403, detail="Only trusted recipients can share responder location")
        if recipient.acknowledged_at is None:
            raise HTTPException(status_code=409, detail="Acknowledge the SOS before sharing responder location")

        enforce_rate(f"responder-location:{alert_id}:{current.id}", limit=120)
        row = db.scalar(
            select(ResponderLocation).where(
                and_(ResponderLocation.alert_id == alert_id, ResponderLocation.responder_user_id == current.id)
            )
        )
        now = utcnow()
        if row is None:
            row = ResponderLocation(
                alert_id=alert_id,
                responder_user_id=current.id,
                latitude=payload.latitude,
                longitude=payload.longitude,
                accuracy_m=payload.accuracy_m,
                speed_mps=payload.speed_mps,
                heading_deg=payload.heading_deg,
                updated_at=now,
            )
            db.add(row)
        else:
            row.latitude = payload.latitude
            row.longitude = payload.longitude
            row.accuracy_m = payload.accuracy_m
            row.speed_mps = payload.speed_mps
            row.heading_deg = payload.heading_deg
            row.updated_at = now
        # Keep a compact responder breadcrumb trail. We store a point when the
        # responder moved meaningfully or enough time elapsed, which filters
        # stationary GPS jitter while preserving real travel.
        last_point = db.scalar(
            select(ResponderLocationPoint)
            .where(
                and_(
                    ResponderLocationPoint.alert_id == alert_id,
                    ResponderLocationPoint.responder_user_id == current.id,
                )
            )
            .order_by(ResponderLocationPoint.recorded_at.desc())
            .limit(1)
        )
        should_store = last_point is None
        if last_point is not None:
            moved_m, _ = _distance_and_bearing(
                last_point.latitude,
                last_point.longitude,
                payload.latitude,
                payload.longitude,
            )
            age_s = max(0.0, (now - ensure_utc(last_point.recorded_at)).total_seconds())
            should_store = moved_m >= 4.0 or age_s >= 12.0
        if should_store:
            db.add(
                ResponderLocationPoint(
                    alert_id=alert_id,
                    responder_user_id=current.id,
                    latitude=payload.latitude,
                    longitude=payload.longitude,
                    accuracy_m=payload.accuracy_m,
                    speed_mps=payload.speed_mps,
                    heading_deg=payload.heading_deg,
                    recorded_at=now,
                )
            )

        audit(db, "responder_location_updated", current.id, alert_id, None)
        db.commit()
        db.refresh(row)
        return _responder_state(db, alert, row)

    @app.get("/alerts/{alert_id}/responders", response_model=list[ResponderStateOut])
    def responder_states(
        alert_id: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert:
            raise HTTPException(status_code=404, detail="Alert not found")
        if not can_view_alert(alert, current.id):
            raise HTTPException(status_code=403, detail="Not allowed to view this emergency")

        acknowledged_ids = {
            r.recipient_user_id for r in alert.recipients
            if r.is_active and r.acknowledged_at is not None
        }
        rows = db.scalars(
            select(ResponderLocation).where(ResponderLocation.alert_id == alert_id)
        ).all()
        # The victim can see every acknowledged responder. A responder only sees
        # their own exact location, avoiding unnecessary contact-to-contact tracking.
        if current.id != alert.owner_id:
            rows = [r for r in rows if r.responder_user_id == current.id]
        else:
            rows = [r for r in rows if r.responder_user_id in acknowledged_ids]
        states = [_responder_state(db, alert, row) for row in rows]
        states.sort(key=lambda item: item.distance_m)
        return states

    @app.get("/alerts/{alert_id}/responder-locations", response_model=list[ResponderTrailPointOut])
    def responder_location_trail(
        alert_id: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert:
            raise HTTPException(status_code=404, detail="Alert not found")
        if not can_view_alert(alert, current.id):
            raise HTTPException(status_code=403, detail="Not allowed to view this emergency")

        responder_id = current.id
        if current.id == alert.owner_id:
            acknowledged_ids = [
                r.recipient_user_id
                for r in alert.recipients
                if r.is_active and r.acknowledged_at is not None
            ]
            if not acknowledged_ids:
                return []
            latest = db.scalar(
                select(ResponderLocation)
                .where(
                    and_(
                        ResponderLocation.alert_id == alert_id,
                        ResponderLocation.responder_user_id.in_(acknowledged_ids),
                    )
                )
                .order_by(ResponderLocation.updated_at.desc())
                .limit(1)
            )
            if latest is None:
                return []
            responder_id = latest.responder_user_id
        else:
            recipient = db.scalar(
                select(AlertRecipient).where(
                    and_(
                        AlertRecipient.alert_id == alert_id,
                        AlertRecipient.recipient_user_id == current.id,
                        AlertRecipient.is_active.is_(True),
                        AlertRecipient.acknowledged_at.is_not(None),
                    )
                )
            )
            if recipient is None:
                return []

        rows = db.scalars(
            select(ResponderLocationPoint)
            .where(
                and_(
                    ResponderLocationPoint.alert_id == alert_id,
                    ResponderLocationPoint.responder_user_id == responder_id,
                )
            )
            .order_by(ResponderLocationPoint.recorded_at.asc())
        ).all()
        rows = rows[-180:]
        return [
            ResponderTrailPointOut(
                latitude=row.latitude,
                longitude=row.longitude,
                accuracy_m=row.accuracy_m,
                speed_mps=row.speed_mps,
                heading_deg=row.heading_deg,
                recorded_at=ensure_utc(row.recorded_at),
            )
            for row in rows
        ]


    # ---------- V1.5 Safety Map anonymous presence ----------
    def _quantise_presence(value: float) -> float:
        # 3 decimal places is roughly a 110 m latitude cell. Exact nearby-user
        # coordinates are never persisted or returned by the presence API.
        return round(value, 3)

    def _distance_and_bearing(lat1: float, lon1: float, lat2: float, lon2: float) -> tuple[float, float]:
        r = 6_371_000.0
        p1, p2 = math.radians(lat1), math.radians(lat2)
        dp = math.radians(lat2 - lat1)
        dl = math.radians(lon2 - lon1)
        a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
        d = 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        y = math.sin(dl) * math.cos(p2)
        x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
        bearing_value = (math.degrees(math.atan2(y, x)) + 360.0) % 360.0
        return d, bearing_value

    @app.post("/presence", response_model=MessageOut)
    def update_presence(
        payload: PresenceUpdateIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        enforce_rate(f"presence:{current.id}:{payload.device_id}", limit=30)
        presence = db.get(SafetyPresenceDevice, payload.device_id)
        now = utcnow()
        if presence is None:
            presence = SafetyPresenceDevice(
                device_id=payload.device_id,
                owner_user_id=current.id,
                coarse_latitude=_quantise_presence(payload.latitude),
                coarse_longitude=_quantise_presence(payload.longitude),
                enabled=payload.enabled,
                last_seen_at=now,
            )
            db.add(presence)
        else:
            # Installation IDs are local random values and survive account
            # changes. Transfer ownership to the currently authenticated user.
            presence.owner_user_id = current.id
            presence.coarse_latitude = _quantise_presence(payload.latitude)
            presence.coarse_longitude = _quantise_presence(payload.longitude)
            presence.enabled = payload.enabled
            presence.last_seen_at = now
        db.commit()
        return MessageOut(message="Anonymous Safety Map presence updated")

    @app.delete("/presence", response_model=MessageOut)
    def disable_presence(
        device_id: str = Query(min_length=8, max_length=80),
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        presence = db.get(SafetyPresenceDevice, device_id)
        if presence is not None and presence.owner_user_id == current.id:
            presence.enabled = False
            presence.last_seen_at = utcnow()
            db.commit()
        return MessageOut(message="Anonymous Safety Map presence disabled")

    @app.get("/presence/nearby", response_model=list[PresencePointOut])
    def nearby_presence(
        device_id: str = Query(min_length=8, max_length=80),
        latitude: float = Query(ge=-90, le=90),
        longitude: float = Query(ge=-180, le=180),
        radius_m: int = Query(default=2000, ge=100, le=5000),
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        now = utcnow()
        cutoff = now - timedelta(seconds=120)
        requester = db.get(SafetyPresenceDevice, device_id)
        if (
            requester is None
            or requester.owner_user_id != current.id
            or not requester.enabled
            or ensure_utc(requester.last_seen_at) < cutoff
        ):
            # Mutual participation: a device must currently share anonymous
            # presence before it can observe other anonymous presence.
            return []
        rows = db.scalars(
            select(SafetyPresenceDevice).where(
                and_(
                    SafetyPresenceDevice.enabled.is_(True),
                    SafetyPresenceDevice.device_id != device_id,
                    SafetyPresenceDevice.last_seen_at >= cutoff,
                )
            )
        ).all()
        out: list[PresencePointOut] = []
        for row in rows:
            distance, bearing_value = _distance_and_bearing(
                latitude, longitude, row.coarse_latitude, row.coarse_longitude
            )
            if distance > radius_m:
                continue
            seen = ensure_utc(row.last_seen_at)
            age = max(0, int((now - seen).total_seconds()))
            out.append(
                PresencePointOut(
                    approx_distance_m=max(50, int(round(distance / 50.0) * 50)),
                    bearing_deg=int(round(bearing_value / 45.0) * 45) % 360,
                    age_seconds=age,
                )
            )
        out.sort(key=lambda point: point.approx_distance_m)
        return out[:40]

    # ---------- V1.5 verified Safe Nodes / Safety Compass ----------
    @app.get("/safe-nodes/nearby", response_model=list[SafeNodeOut])
    def nearby_safe_nodes(
        latitude: float = Query(ge=-90, le=90),
        longitude: float = Query(ge=-180, le=180),
        radius_m: int = Query(default=5000, ge=100, le=25000),
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        # Safe Nodes are operator-configured public places. Only nodes explicitly
        # marked verified and active are exposed to users.
        rows = db.scalars(
            select(SafeNode).where(and_(SafeNode.active.is_(True), SafeNode.verified.is_(True)))
        ).all()
        out: list[SafeNodeOut] = []
        for row in rows:
            distance, bearing_value = _distance_and_bearing(latitude, longitude, row.latitude, row.longitude)
            if distance > radius_m:
                continue
            out.append(
                SafeNodeOut(
                    id=row.id,
                    name=row.name,
                    category=row.category,
                    latitude=row.latitude,
                    longitude=row.longitude,
                    phone_e164=row.phone_e164,
                    address=row.address,
                    verified=row.verified,
                    approx_distance_m=max(1, int(round(distance))),
                    bearing_deg=int(round(bearing_value)) % 360,
                )
            )
        out.sort(key=lambda node: node.approx_distance_m)
        return out[:50]

    # Journey Guard was intentionally removed from the V1.4.3 product surface.
    # The legacy table is retained for non-destructive database compatibility.

    @app.get("/audit/recent", response_model=list[AuditEventOut])
    def recent_audit(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        events = db.scalars(
            select(AuditEvent)
            .where(AuditEvent.actor_user_id == current.id)
            .order_by(AuditEvent.created_at.desc())
            .limit(50)
        ).all()
        return [AuditEventOut(event_type=e.event_type, resource_id=e.resource_id, detail=e.detail, created_at=ensure_utc(e.created_at)) for e in events]

    return app


app = create_app()
