from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import and_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from .config import Settings, settings as default_settings
from .db import Base, build_engine, build_session_factory
from .models import Alert, AlertRecipient, ContactStatus, TrustedContact, User, utcnow
from .schemas import (
    AlertCreateIn,
    AlertOut,
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


def create_app(*, database_path: str | None = None, settings: Settings | None = None) -> FastAPI:
    cfg = settings or default_settings
    db_path = database_path or cfg.database_path
    engine = build_engine(db_path)
    SessionLocal = build_session_factory(engine)
    Base.metadata.create_all(engine)

    app = FastAPI(
        title="ViraNari API",
        version="0.1.0",
        description="Hackathon-ready emergency alert backend with trusted contacts, delivery receipts and idempotent retries.",
    )
    app.state.engine = engine
    app.state.SessionLocal = SessionLocal
    app.state.settings = cfg

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
            note=alert.note,
            created_at=alert.created_at,
            cancelled_at=alert.cancelled_at,
            recipients=recipients,
        )

    @app.get("/health")
    def health():
        return {"status": "ok", "service": "viranari-api", "version": "0.1.0"}

    @app.post("/auth/register", response_model=TokenOut, status_code=201)
    def register(payload: RegisterIn, db: Session = Depends(get_db)):
        email = payload.email.lower().strip()
        user = User(name=payload.name.strip(), email=email, password_hash=hash_password(payload.password))
        db.add(user)
        try:
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
        db.commit()
        return MessageOut(message="Trusted contact removed")

    @app.post("/alerts", response_model=AlertOut, status_code=201)
    def create_alert(
        payload: AlertCreateIn,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        existing = db.scalar(select(Alert).where(Alert.idempotency_key == payload.idempotency_key))
        if existing:
            if existing.owner_id != current.id:
                raise HTTPException(status_code=409, detail="Idempotency key already in use")
            existing = db.scalar(
                select(Alert).options(joinedload(Alert.recipients)).where(Alert.id == existing.id)
            )
            return alert_out(db, existing)

        alert = Alert(
            owner_id=current.id,
            idempotency_key=payload.idempotency_key,
            latitude=payload.latitude,
            longitude=payload.longitude,
            accuracy_m=payload.accuracy_m,
            battery_percent=payload.battery_percent,
            note=payload.note,
        )
        db.add(alert)
        db.flush()

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

        db.commit()
        result = db.scalar(select(Alert).options(joinedload(Alert.recipients)).where(Alert.id == alert.id))
        return alert_out(db, result)

    @app.get("/alerts/by-idempotency/{key}", response_model=AlertOut)
    def alert_by_idempotency(
        key: str,
        current: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ):
        alert = db.scalar(
            select(Alert).options(joinedload(Alert.recipients)).where(Alert.idempotency_key == key)
        )
        if not alert or alert.owner_id != current.id:
            raise HTTPException(status_code=404, detail="Alert not found")
        return alert_out(db, alert)

    @app.get("/alerts/history", response_model=list[AlertOut])
    def alert_history(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        alerts = db.scalars(
            select(Alert)
            .options(joinedload(Alert.recipients))
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
        alert = db.scalar(
            select(Alert).options(joinedload(Alert.recipients)).where(Alert.id == alert_id)
        )
        if not alert:
            raise HTTPException(status_code=404, detail="Alert not found")
        recipient_ids = {r.recipient_user_id for r in alert.recipients}
        if current.id != alert.owner_id and current.id not in recipient_ids:
            raise HTTPException(status_code=403, detail="Not allowed to view this alert")
        return alert_out(db, alert)

    @app.get("/alerts/inbox", response_model=list[InboxAlertOut])
    def inbox(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        rows = db.execute(
            select(AlertRecipient, Alert, User)
            .join(Alert, AlertRecipient.alert_id == Alert.id)
            .join(User, Alert.owner_id == User.id)
            .where(AlertRecipient.recipient_user_id == current.id)
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
                    note=alert.note,
                    created_at=alert.created_at,
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
                )
            )
        )
        if not recipient:
            raise HTTPException(status_code=404, detail="Alert not found in your inbox")
        if recipient.delivered_at is None:
            recipient.delivered_at = utcnow()
        if recipient.acknowledged_at is None:
            recipient.acknowledged_at = utcnow()
        db.commit()
        return MessageOut(message="Alert acknowledged")

    return app


app = create_app()
