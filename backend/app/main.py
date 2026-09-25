from __future__ import annotations

import logging
import secrets
from collections import defaultdict, deque
from threading import Lock
from time import monotonic
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import and_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from .config import Settings, settings as default_settings
from .db import Base, build_engine, build_session_factory
from .models import (
    Alert,
    AlertLocation,
    AuditEvent,
    AlertRecipient,
    AlertState,
    ContactStatus,
    TrustedContact,
    User,
    utcnow,
)
from .schemas import (
    AlertCreateIn,
    AlertLocationIn,
    AlertLocationOut,
    AlertOut,
    AuditEventOut,
    ContactAcceptIn,
    ContactCreateIn,
    ContactOut,
    InboxAlertOut,
    LoginIn,
    MessageOut,
    RecipientStatusOut,
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
    Base.metadata.create_all(engine)

    app = FastAPI(
        title="ViraNari API",
        version="1.2.0",
        description=(
            "Emergency-response API with consent-based trusted contacts, delivery receipts, "
            "idempotent offline retry, live emergency sessions, and location updates."
        ),
    )
    app.state.engine = engine
    app.state.SessionLocal = SessionLocal
    app.state.settings = cfg
    limiter = SlidingWindowLimiter()

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
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

    def user_out(user: User) -> UserOut:
        return UserOut(id=user.id, name=user.name, email=user.email)

    def contact_out(db: Session, contact: TrustedContact, include_token: bool = False) -> ContactOut:
        target = db.get(User, contact.contact_user_id)
        return ContactOut(
            id=contact.id,
            contact_user_id=contact.contact_user_id,
            contact_name=target.name,
            contact_email=target.email,
            alias=contact.alias,
            status=contact.status,
            invite_token=contact.invite_token if include_token and contact.status == ContactStatus.pending.value else None,
            invite_expires_at=contact.invite_expires_at,
            accepted_at=contact.accepted_at,
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
                    delivered_at=r.delivered_at,
                    acknowledged_at=r.acknowledged_at,
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
            note=alert.note,
            state=alert.state,
            created_at=alert.created_at,
            updated_at=alert.updated_at,
            cancelled_at=alert.cancelled_at,
            resolved_at=alert.resolved_at,
            recipients=recipients,
        )

    @app.get("/health")
    def health():
        return {"status": "ok", "service": "viranari-api", "version": "1.2.0"}

    @app.post("/auth/register", response_model=TokenOut, status_code=201)
    def register(payload: RegisterIn, db: Session = Depends(get_db)):
        email = payload.email.lower().strip()
        user = User(name=payload.name.strip(), email=email, password_hash=hash_password(payload.password))
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
            note=payload.note,
            state=AlertState.active.value,
            updated_at=now,
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

        audit(db, "sos_created_test" if payload.is_test else "sos_created", current.id, alert.id, f"recipients={len(active_contacts)}")
        logger.info("sos_created user=%s alert=%s recipients=%s test=%s", current.id, alert.id, len(active_contacts), payload.is_test)
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
        db.add(
            AlertLocation(
                alert_id=alert.id,
                latitude=payload.latitude,
                longitude=payload.longitude,
                accuracy_m=payload.accuracy_m,
                battery_percent=payload.battery_percent,
                network_state=payload.network_state,
                recorded_at=now,
            )
        )
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
                recorded_at=p.recorded_at,
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
                    latitude=alert.latitude,
                    longitude=alert.longitude,
                    accuracy_m=alert.accuracy_m,
                    battery_percent=alert.battery_percent,
                    network_state=alert.network_state,
                    is_test=alert.is_test,
                    state=alert.state,
                    note=alert.note,
                    created_at=alert.created_at,
                    updated_at=alert.updated_at,
                    delivered_at=recipient.delivered_at,
                    acknowledged_at=recipient.acknowledged_at,
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

    @app.get("/audit/recent", response_model=list[AuditEventOut])
    def recent_audit(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        events = db.scalars(
            select(AuditEvent)
            .where(AuditEvent.actor_user_id == current.id)
            .order_by(AuditEvent.created_at.desc())
            .limit(50)
        ).all()
        return [AuditEventOut(event_type=e.event_type, resource_id=e.resource_id, detail=e.detail, created_at=e.created_at) for e in events]

    return app


app = create_app()
