from __future__ import annotations

import json
import logging
import math
import secrets
from collections import defaultdict, deque
from threading import Lock
from time import monotonic
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, FastAPI, Header, HTTPException
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
    IncidentEvent,
    ResponderAssignment,
    ResponderProfile,
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
    ProofChainOut,
    ProofEventOut,
    ProofPublicKeyOut,
    ProofVerificationOut,
    RecipientStatusOut,
    RegisterIn,
    ResponderAssignmentOut,
    ResponderIncidentOut,
    ResponderProfileOut,
    ResponderProfileUpdateIn,
    ResponderVerifyIn,
    TokenOut,
    UserOut,
)
from .proofchain import ProofSigner, canonical_json, sha256_hex
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
        version="1.5.0",
        description=(
            "ViraNari emergency-response API preserving V1.4.4 live tracking and timeline, "
            "with SafeReach verified responder routing and Ed25519-signed ProofChain incident logs."
        ),
    )
    app.state.engine = engine
    app.state.SessionLocal = SessionLocal
    app.state.settings = cfg
    signer = ProofSigner(cfg.proof_key_path)
    app.state.proof_signer = signer
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
        return UserOut(id=user.id, name=user.name, email=user.email, phone_e164=user.phone_e164, role=user.role or "traveler")

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

    def responder_profile_out(db: Session, profile: ResponderProfile) -> ResponderProfileOut:
        user = db.get(User, profile.user_id)
        return ResponderProfileOut(
            id=profile.id,
            user_id=profile.user_id,
            responder_name=user.name if user else "Verified responder",
            organization_name=profile.organization_name,
            category=profile.category,
            verification_status=profile.verification_status,
            is_available=profile.is_available,
            service_radius_m=profile.service_radius_m,
            latitude=profile.latitude,
            longitude=profile.longitude,
            last_seen_at=ensure_utc(profile.last_seen_at),
        )

    def current_assignment(db: Session, alert_id: str) -> ResponderAssignment | None:
        return db.scalar(
            select(ResponderAssignment)
            .where(ResponderAssignment.alert_id == alert_id)
            .order_by(ResponderAssignment.offered_at.desc())
            .limit(1)
        )

    def responder_assignment_out(db: Session, assignment: ResponderAssignment | None) -> ResponderAssignmentOut | None:
        if assignment is None:
            return None
        profile = db.get(ResponderProfile, assignment.responder_profile_id)
        if profile is None:
            return None
        user = db.get(User, profile.user_id)
        return ResponderAssignmentOut(
            assignment_id=assignment.id,
            responder_profile_id=profile.id,
            responder_name=user.name if user else "Verified responder",
            organization_name=profile.organization_name,
            category=profile.category,
            phone_e164=user.phone_e164 if user else None,
            state=assignment.state,
            distance_m=assignment.distance_m,
            offered_at=ensure_utc(assignment.offered_at),
            accepted_at=ensure_utc(assignment.accepted_at),
            arrived_at=ensure_utc(assignment.arrived_at),
            completed_at=ensure_utc(assignment.completed_at),
        )

    def alert_query():
        return select(Alert).options(joinedload(Alert.recipients), joinedload(Alert.locations))

    def can_view_alert(alert: Alert, user_id: str) -> bool:
        if alert.owner_id == user_id:
            return True
        return any(r.recipient_user_id == user_id and r.is_active for r in alert.recipients)

    def assigned_responder_can_view(db: Session, alert_id: str, user_id: str) -> bool:
        assignment = current_assignment(db, alert_id)
        if assignment is None:
            return False
        profile = db.get(ResponderProfile, assignment.responder_profile_id)
        return profile is not None and profile.user_id == user_id

    def can_view_alert_with_db(db: Session, alert: Alert, user_id: str) -> bool:
        return can_view_alert(alert, user_id) or assigned_responder_can_view(db, alert.id, user_id)

    def append_incident_event(
        db: Session,
        *,
        alert_id: str,
        event_type: str,
        actor_type: str = "system",
        actor_user_id: str | None = None,
        payload: dict | None = None,
    ) -> IncidentEvent:
        latest = db.scalar(
            select(IncidentEvent)
            .where(IncidentEvent.alert_id == alert_id)
            .order_by(IncidentEvent.sequence.desc())
            .limit(1)
        )
        sequence = 1 if latest is None else latest.sequence + 1
        previous_hash = "0" * 64 if latest is None else latest.event_hash
        created_at = utcnow()
        normalized_payload = payload or {}
        body = {
            "alert_id": alert_id,
            "sequence": sequence,
            "event_type": event_type,
            "actor_type": actor_type,
            "actor_user_id": actor_user_id,
            "payload": normalized_payload,
            "previous_hash": previous_hash,
            "created_at": created_at.isoformat(),
        }
        event_hash = sha256_hex(canonical_json(body))
        event = IncidentEvent(
            alert_id=alert_id,
            sequence=sequence,
            event_type=event_type,
            actor_type=actor_type,
            actor_user_id=actor_user_id,
            payload_json=canonical_json(normalized_payload),
            previous_hash=previous_hash,
            event_hash=event_hash,
            signature=signer.sign_hash(event_hash),
            key_id=signer.key_id,
            created_at=created_at,
        )
        db.add(event)
        db.flush()
        return event

    def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        radius = 6371000.0
        p1 = math.radians(lat1)
        p2 = math.radians(lat2)
        dp = math.radians(lat2 - lat1)
        dl = math.radians(lon2 - lon1)
        a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
        return 2 * radius * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    def match_nearest_responder(db: Session, alert: Alert, *, reason: str = "automatic") -> ResponderAssignment | None:
        existing = current_assignment(db, alert.id)
        if existing is not None and existing.state not in {"declined", "completed", "cancelled", "expired"}:
            return existing
        excluded = set(
            db.scalars(
                select(ResponderAssignment.responder_profile_id).where(ResponderAssignment.alert_id == alert.id)
            ).all()
        )

        cutoff = utcnow() - timedelta(minutes=cfg.responder_location_ttl_minutes)
        profiles = db.scalars(
            select(ResponderProfile).where(
                and_(
                    ResponderProfile.verification_status == "verified",
                    ResponderProfile.is_available.is_(True),
                    ResponderProfile.latitude.is_not(None),
                    ResponderProfile.longitude.is_not(None),
                    ResponderProfile.last_seen_at.is_not(None),
                    ResponderProfile.last_seen_at >= cutoff,
                )
            )
        ).all()
        best: tuple[ResponderProfile, float] | None = None
        for profile in profiles:
            if profile.id in excluded or profile.user_id == alert.owner_id:
                continue
            distance = haversine_m(alert.latitude, alert.longitude, profile.latitude, profile.longitude)
            if distance > profile.service_radius_m:
                continue
            if best is None or distance < best[1]:
                best = (profile, distance)

        if best is None:
            append_incident_event(
                db, alert_id=alert.id, event_type="SAFE_REACH_NO_RESPONDER",
                payload={"reason": reason, "search_ttl_minutes": cfg.responder_location_ttl_minutes},
            )
            return None

        profile, distance = best
        now = utcnow()
        assignment = ResponderAssignment(
            alert_id=alert.id, responder_profile_id=profile.id, state="offered",
            distance_m=distance, offered_at=now,
        )
        db.add(assignment)
        db.flush()
        append_incident_event(
            db, alert_id=alert.id, event_type="SAFE_REACH_RESPONDER_MATCHED",
            payload={
                "reason": reason,
                "responder_profile_id": profile.id,
                "organization_name": profile.organization_name,
                "category": profile.category,
                "distance_m": round(distance, 1),
            },
        )
        return assignment

    def proof_event_out(event: IncidentEvent) -> ProofEventOut:
        return ProofEventOut(
            id=event.id, sequence=event.sequence, event_type=event.event_type, actor_type=event.actor_type,
            actor_user_id=event.actor_user_id, payload=json.loads(event.payload_json), previous_hash=event.previous_hash,
            event_hash=event.event_hash, signature=event.signature, key_id=event.key_id, created_at=ensure_utc(event.created_at),
        )

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
            note=alert.note,
            state=alert.state,
            created_at=ensure_utc(alert.created_at),
            updated_at=ensure_utc(alert.updated_at),
            cancelled_at=ensure_utc(alert.cancelled_at),
            resolved_at=ensure_utc(alert.resolved_at),
            last_device_seen_at=ensure_utc(alert.last_device_seen_at),
            last_gps_fix_at=ensure_utc(alert.last_gps_fix_at),
            last_location_sync_at=ensure_utc(alert.last_location_sync_at),
            safe_reach=responder_assignment_out(db, current_assignment(db, alert.id)),
            recipients=recipients,
        )

    @app.get("/health")
    def health():
        return {"status": "ok", "service": "viranari-api", "version": "1.5.0", "safe_reach": True, "proofchain": "ed25519-sha256"}

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

        audit(db, "sos_created_test" if payload.is_test else "sos_created", current.id, alert.id, f"recipients={len(active_contacts)}")
        append_incident_event(
            db, alert_id=alert.id, event_type="SOS_CREATED_TEST" if payload.is_test else "SOS_CREATED",
            actor_type="traveler", actor_user_id=current.id,
            payload={
                "recipient_count": len(active_contacts),
                "latitude": round(payload.latitude, 6),
                "longitude": round(payload.longitude, 6),
                "accuracy_m": payload.accuracy_m,
                "network_state": payload.network_state,
            },
        )
        append_incident_event(
            db, alert_id=alert.id, event_type="TRUSTED_CIRCLE_NOTIFIED",
            payload={"recipient_count": len(active_contacts)},
        )
        # Test drills can exercise the complete SafeReach flow without claiming a real emergency.
        match_nearest_responder(db, alert, reason="test_drill" if payload.is_test else "sos_created")
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
        if not can_view_alert_with_db(db, alert, current.id):
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
        append_incident_event(
            db, alert_id=alert.id, event_type="LOCATION_FIX_STORED", actor_type="device", actor_user_id=current.id,
            payload={"latitude": round(payload.latitude, 6), "longitude": round(payload.longitude, 6), "accuracy_m": payload.accuracy_m},
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
            append_incident_event(
                db, alert_id=alert.id, event_type="OFFLINE_LOCATION_BATCH_REPLAYED", actor_type="device", actor_user_id=current.id,
                payload={"accepted": accepted, "latest_recorded_at": latest_recorded.isoformat() if latest_recorded else None},
            )

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

        # Industry-style escalation: an unanswered responder offer expires and
        # the next eligible verified responder is tried automatically.
        assignment = current_assignment(db, alert.id)
        if assignment is not None and assignment.state == "offered":
            offered_at = ensure_utc(assignment.offered_at)
            if offered_at is not None and now - offered_at >= timedelta(seconds=cfg.responder_offer_timeout_seconds):
                assignment.state = "expired"
                append_incident_event(
                    db, alert_id=alert.id, event_type="SAFE_REACH_OFFER_EXPIRED",
                    payload={"assignment_id": assignment.id, "timeout_seconds": cfg.responder_offer_timeout_seconds},
                )
                match_nearest_responder(db, alert, reason="offer_timeout")
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
        if not can_view_alert_with_db(db, alert, current.id):
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
        append_incident_event(
            db, alert_id=alert.id, event_type=f"SOS_{target_state.value.upper()}",
            actor_type="traveler", actor_user_id=current.id, payload={"state": target_state.value},
        )
        assignment = current_assignment(db, alert.id)
        if assignment is not None:
            profile = db.get(ResponderProfile, assignment.responder_profile_id)
            if profile is not None:
                profile.is_available = True
                profile.updated_at = now
            if target_state is AlertState.resolved and assignment.state != "completed":
                assignment.state = "completed"
                assignment.completed_at = now
            elif target_state is AlertState.cancelled and assignment.state not in {"completed", "declined"}:
                assignment.state = "cancelled"
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
                append_incident_event(
                    db, alert_id=alert.id, event_type="TRUSTED_CONTACT_DELIVERY_CONFIRMED",
                    actor_type="trusted_contact", actor_user_id=current.id, payload={"recipient_user_id": current.id},
                )
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
                    state=alert.state,
                    note=alert.note,
                    created_at=ensure_utc(alert.created_at),
                    updated_at=ensure_utc(alert.updated_at),
                    delivered_at=ensure_utc(recipient.delivered_at),
                    acknowledged_at=ensure_utc(recipient.acknowledged_at),
                    last_device_seen_at=ensure_utc(alert.last_device_seen_at),
                    last_gps_fix_at=ensure_utc(alert.last_gps_fix_at),
                    last_location_sync_at=ensure_utc(alert.last_location_sync_at),
                    safe_reach=responder_assignment_out(db, current_assignment(db, alert.id)),
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
        append_incident_event(
            db, alert_id=alert_id, event_type="TRUSTED_CONTACT_ACKNOWLEDGED",
            actor_type="trusted_contact", actor_user_id=current.id, payload={"recipient_user_id": current.id},
        )
        db.commit()
        return MessageOut(message="Alert acknowledged")

    @app.get("/proof/public-key", response_model=ProofPublicKeyOut)
    def proof_public_key():
        return ProofPublicKeyOut(key_id=signer.key_id, public_key_b64=signer.public_key_b64())

    @app.get("/alerts/{alert_id}/proof", response_model=ProofChainOut)
    def incident_proof(
        alert_id: str, current: User = Depends(get_current_user), db: Session = Depends(get_db),
    ):
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert:
            raise HTTPException(status_code=404, detail="Alert not found")
        if not can_view_alert_with_db(db, alert, current.id):
            raise HTTPException(status_code=403, detail="Not allowed to view this incident proof")
        events = db.scalars(
            select(IncidentEvent).where(IncidentEvent.alert_id == alert_id).order_by(IncidentEvent.sequence.asc())
        ).all()
        return ProofChainOut(
            alert_id=alert_id, key_id=signer.key_id, public_key_b64=signer.public_key_b64(),
            events=[proof_event_out(e) for e in events],
        )

    @app.get("/alerts/{alert_id}/proof/verify", response_model=ProofVerificationOut)
    def verify_incident_proof(
        alert_id: str, current: User = Depends(get_current_user), db: Session = Depends(get_db),
    ):
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert:
            raise HTTPException(status_code=404, detail="Alert not found")
        if not can_view_alert_with_db(db, alert, current.id):
            raise HTTPException(status_code=403, detail="Not allowed to verify this incident proof")
        events = db.scalars(
            select(IncidentEvent).where(IncidentEvent.alert_id == alert_id).order_by(IncidentEvent.sequence.asc())
        ).all()
        expected_prev = "0" * 64
        hash_valid = True
        sig_valid = True
        first_invalid: int | None = None
        for event in events:
            created = ensure_utc(event.created_at)
            body = {
                "alert_id": alert_id,
                "sequence": event.sequence,
                "event_type": event.event_type,
                "actor_type": event.actor_type,
                "actor_user_id": event.actor_user_id,
                "payload": json.loads(event.payload_json),
                "previous_hash": event.previous_hash,
                "created_at": created.isoformat(),
            }
            calculated = sha256_hex(canonical_json(body))
            row_hash_ok = event.previous_hash == expected_prev and calculated == event.event_hash
            row_sig_ok = signer.verify_hash(event.event_hash, event.signature) and event.key_id == signer.key_id
            if not row_hash_ok:
                hash_valid = False
            if not row_sig_ok:
                sig_valid = False
            if first_invalid is None and (not row_hash_ok or not row_sig_ok):
                first_invalid = event.sequence
            expected_prev = event.event_hash
        return ProofVerificationOut(
            alert_id=alert_id, valid=hash_valid and sig_valid, event_count=len(events),
            hash_chain_valid=hash_valid, signatures_valid=sig_valid, key_id=signer.key_id,
            first_invalid_sequence=first_invalid,
        )

    def require_admin_key(x_viranari_admin_key: str | None = Header(default=None)) -> None:
        if not cfg.admin_key:
            raise HTTPException(status_code=503, detail="Responder administration is not configured")
        if not x_viranari_admin_key or not secrets.compare_digest(x_viranari_admin_key, cfg.admin_key):
            raise HTTPException(status_code=403, detail="Invalid responder administration key")

    @app.post("/admin/responders/verify", response_model=ResponderProfileOut)
    def verify_responder(
        payload: ResponderVerifyIn,
        _: None = Depends(require_admin_key),
        db: Session = Depends(get_db),
    ):
        user = db.scalar(select(User).where(User.email == payload.user_email.lower().strip()))
        if not user:
            raise HTTPException(status_code=404, detail="Responder user must register first")
        profile = db.scalar(select(ResponderProfile).where(ResponderProfile.user_id == user.id))
        now = utcnow()
        if profile is None:
            profile = ResponderProfile(
                user_id=user.id, organization_name=payload.organization_name.strip(), category=payload.category.strip(),
                verification_status="verified", verified_at=now, is_available=payload.is_available,
                service_radius_m=payload.service_radius_m, latitude=payload.latitude, longitude=payload.longitude,
                last_seen_at=now if payload.latitude is not None and payload.longitude is not None else None, updated_at=now,
            )
            db.add(profile)
        else:
            profile.organization_name = payload.organization_name.strip()
            profile.category = payload.category.strip()
            profile.verification_status = "verified"
            profile.verified_at = now
            profile.is_available = payload.is_available
            profile.service_radius_m = payload.service_radius_m
            profile.latitude = payload.latitude
            profile.longitude = payload.longitude
            if payload.latitude is not None and payload.longitude is not None:
                profile.last_seen_at = now
            profile.updated_at = now
        user.role = "responder"
        db.commit()
        db.refresh(profile)
        return responder_profile_out(db, profile)

    def require_responder(current: User, db: Session) -> ResponderProfile:
        profile = db.scalar(select(ResponderProfile).where(ResponderProfile.user_id == current.id))
        if current.role != "responder" or profile is None or profile.verification_status != "verified":
            raise HTTPException(status_code=403, detail="Verified responder access required")
        return profile

    @app.get("/responders/me", response_model=ResponderProfileOut)
    def responder_me(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        return responder_profile_out(db, require_responder(current, db))

    @app.patch("/responders/me/status", response_model=ResponderProfileOut)
    def responder_update_status(
        payload: ResponderProfileUpdateIn, current: User = Depends(get_current_user), db: Session = Depends(get_db),
    ):
        profile = require_responder(current, db)
        profile.latitude = payload.latitude
        profile.longitude = payload.longitude
        profile.is_available = payload.is_available
        if payload.service_radius_m is not None:
            profile.service_radius_m = payload.service_radius_m
        profile.last_seen_at = utcnow()
        profile.updated_at = utcnow()
        db.commit()
        db.refresh(profile)
        return responder_profile_out(db, profile)

    @app.get("/responders/incidents", response_model=list[ResponderIncidentOut])
    def responder_incidents(current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        profile = require_responder(current, db)
        assignments = db.scalars(
            select(ResponderAssignment)
            .where(ResponderAssignment.responder_profile_id == profile.id)
            .order_by(ResponderAssignment.offered_at.desc())
            .limit(50)
        ).all()
        output: list[ResponderIncidentOut] = []
        for assignment in assignments:
            alert = db.get(Alert, assignment.alert_id)
            if alert is None:
                continue
            sender = db.get(User, alert.owner_id)
            output.append(ResponderIncidentOut(
                alert_id=alert.id, sender_name=sender.name, sender_phone_e164=sender.phone_e164,
                latitude=alert.latitude, longitude=alert.longitude, accuracy_m=alert.accuracy_m,
                note=alert.note, state=alert.state, assignment=responder_assignment_out(db, assignment),
            ))
        return output

    def responder_transition(alert_id: str, target: str, current: User, db: Session) -> ResponderAssignmentOut:
        profile = require_responder(current, db)
        assignment = current_assignment(db, alert_id)
        if assignment is None or assignment.responder_profile_id != profile.id:
            raise HTTPException(status_code=404, detail="Incident is not assigned to this responder")
        now = utcnow()
        allowed = {
            "accepted": {"offered"},
            "arrived": {"accepted"},
            "completed": {"accepted", "arrived"},
            "declined": {"offered"},
        }
        if assignment.state == target:
            return responder_assignment_out(db, assignment)
        if assignment.state not in allowed[target]:
            raise HTTPException(status_code=409, detail=f"Cannot move responder state from {assignment.state} to {target}")
        assignment.state = target
        if target == "accepted":
            assignment.accepted_at = now
        elif target == "arrived":
            assignment.arrived_at = now
        elif target == "completed":
            assignment.completed_at = now
            profile.is_available = True
        elif target == "declined":
            assignment.declined_at = now
            profile.is_available = True
        if target in {"accepted", "arrived"}:
            profile.is_available = False
        append_incident_event(
            db, alert_id=alert_id, event_type=f"SAFE_REACH_{target.upper()}",
            actor_type="verified_responder", actor_user_id=current.id,
            payload={"responder_profile_id": profile.id, "organization_name": profile.organization_name},
        )
        if target == "declined":
            alert = db.get(Alert, alert_id)
            if alert is not None and alert.state == AlertState.active.value:
                match_nearest_responder(db, alert, reason="responder_declined")
        db.commit()
        return responder_assignment_out(db, assignment)

    @app.post("/responders/incidents/{alert_id}/accept", response_model=ResponderAssignmentOut)
    def responder_accept(alert_id: str, current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        return responder_transition(alert_id, "accepted", current, db)

    @app.post("/responders/incidents/{alert_id}/arrive", response_model=ResponderAssignmentOut)
    def responder_arrive(alert_id: str, current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        return responder_transition(alert_id, "arrived", current, db)

    @app.post("/responders/incidents/{alert_id}/complete", response_model=ResponderAssignmentOut)
    def responder_complete(alert_id: str, current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        return responder_transition(alert_id, "completed", current, db)

    @app.post("/responders/incidents/{alert_id}/decline", response_model=ResponderAssignmentOut)
    def responder_decline(alert_id: str, current: User = Depends(get_current_user), db: Session = Depends(get_db)):
        return responder_transition(alert_id, "declined", current, db)

    @app.post("/alerts/{alert_id}/safe-reach/rematch", response_model=AlertOut)
    def safe_reach_rematch(
        alert_id: str, current: User = Depends(get_current_user), db: Session = Depends(get_db),
    ):
        alert = db.scalar(alert_query().where(Alert.id == alert_id))
        if not alert or alert.owner_id != current.id:
            raise HTTPException(status_code=404, detail="Alert not found")
        if alert.state != AlertState.active.value:
            raise HTTPException(status_code=409, detail="Emergency session is not active")
        existing = current_assignment(db, alert.id)
        if existing is not None and existing.state not in {"declined", "completed", "cancelled", "expired"}:
            existing.state = "declined"
            existing.declined_at = utcnow()
        match_nearest_responder(db, alert, reason="traveler_requested_rematch")
        db.commit()
        result = db.scalar(alert_query().where(Alert.id == alert.id))
        return alert_out(db, result)

    # Journey Guard was intentionally removed from the V1.4.4 product surface.
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
