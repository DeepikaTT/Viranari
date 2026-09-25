from __future__ import annotations

from datetime import datetime
from pydantic import BaseModel, EmailStr, Field

PHONE_PATTERN = r"^\+[1-9][0-9]{7,14}$"


class RegisterIn(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    email: EmailStr
    phone_e164: str | None = Field(default=None, pattern=PHONE_PATTERN)
    password: str = Field(min_length=8, max_length=128)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class PhoneUpdateIn(BaseModel):
    phone_e164: str = Field(pattern=PHONE_PATTERN)


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: "UserOut"


class UserOut(BaseModel):
    id: str
    name: str
    email: EmailStr
    phone_e164: str | None = None


class ContactCreateIn(BaseModel):
    email: EmailStr
    alias: str = Field(default="Trusted contact", max_length=80)


class ContactAcceptIn(BaseModel):
    invite_token: str


class ContactOut(BaseModel):
    id: str
    contact_user_id: str
    contact_name: str
    contact_email: EmailStr
    contact_phone_e164: str | None = None
    alias: str
    status: str
    invite_token: str | None = None
    invite_expires_at: datetime
    accepted_at: datetime | None = None


class AlertCreateIn(BaseModel):
    idempotency_key: str = Field(min_length=8, max_length=100)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)
    battery_percent: int | None = Field(default=None, ge=0, le=100)
    network_state: str | None = Field(default=None, max_length=40)
    speed_mps: float | None = Field(default=None, ge=0)
    heading_deg: float | None = Field(default=None, ge=0, lt=360)
    is_test: bool = False
    note: str | None = Field(default=None, max_length=500)


class AlertLocationIn(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)
    battery_percent: int | None = Field(default=None, ge=0, le=100)
    network_state: str | None = Field(default=None, max_length=40)
    speed_mps: float | None = Field(default=None, ge=0)
    heading_deg: float | None = Field(default=None, ge=0, lt=360)


class QueuedAlertLocationIn(AlertLocationIn):
    recorded_at: datetime


class AlertLocationBatchIn(BaseModel):
    points: list[QueuedAlertLocationIn] = Field(min_length=1, max_length=120)


class AlertLocationBatchOut(BaseModel):
    accepted: int


class AlertHeartbeatIn(BaseModel):
    battery_percent: int | None = Field(default=None, ge=0, le=100)
    network_state: str | None = Field(default=None, max_length=40)
    last_gps_fix_at: datetime | None = None


class AlertLocationOut(BaseModel):
    latitude: float
    longitude: float
    accuracy_m: float | None
    battery_percent: int | None
    network_state: str | None
    speed_mps: float | None
    heading_deg: float | None
    recorded_at: datetime


class RecipientStatusOut(BaseModel):
    recipient_user_id: str
    recipient_name: str
    delivered_at: datetime | None
    acknowledged_at: datetime | None


class AlertOut(BaseModel):
    id: str
    owner_id: str
    owner_name: str
    idempotency_key: str
    latitude: float
    longitude: float
    accuracy_m: float | None
    battery_percent: int | None
    network_state: str | None
    is_test: bool
    note: str | None
    state: str
    created_at: datetime
    updated_at: datetime
    cancelled_at: datetime | None
    resolved_at: datetime | None
    last_device_seen_at: datetime | None
    last_gps_fix_at: datetime | None
    last_location_sync_at: datetime | None
    recipients: list[RecipientStatusOut]


class InboxAlertOut(BaseModel):
    alert_id: str
    sender_name: str
    sender_email: EmailStr
    sender_phone_e164: str | None = None
    latitude: float
    longitude: float
    accuracy_m: float | None
    battery_percent: int | None
    network_state: str | None
    is_test: bool
    state: str
    note: str | None
    created_at: datetime
    updated_at: datetime
    delivered_at: datetime | None
    acknowledged_at: datetime | None
    last_device_seen_at: datetime | None
    last_gps_fix_at: datetime | None
    last_location_sync_at: datetime | None


class PresenceUpdateIn(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    enabled: bool = True


class PresencePointOut(BaseModel):
    approx_distance_m: int
    bearing_deg: int
    age_seconds: int


class JourneyCreateIn(BaseModel):
    destination_label: str = Field(min_length=2, max_length=120)
    duration_minutes: int = Field(ge=5, le=720)
    start_latitude: float | None = Field(default=None, ge=-90, le=90)
    start_longitude: float | None = Field(default=None, ge=-180, le=180)


class JourneyOut(BaseModel):
    id: str
    owner_id: str
    owner_name: str
    owner_phone_e164: str | None = None
    destination_label: str
    expected_arrival_at: datetime
    state: str
    start_latitude: float | None
    start_longitude: float | None
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None
    overdue: bool


class MessageOut(BaseModel):
    message: str


class AuditEventOut(BaseModel):
    event_type: str
    resource_id: str | None
    detail: str | None
    created_at: datetime
