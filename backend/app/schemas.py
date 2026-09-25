from __future__ import annotations

from datetime import datetime
from pydantic import BaseModel, EmailStr, Field


class RegisterIn(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: "UserOut"


class UserOut(BaseModel):
    id: str
    name: str
    email: EmailStr


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
    is_test: bool = False
    note: str | None = Field(default=None, max_length=500)


class AlertLocationIn(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)
    battery_percent: int | None = Field(default=None, ge=0, le=100)
    network_state: str | None = Field(default=None, max_length=40)


class AlertLocationOut(BaseModel):
    latitude: float
    longitude: float
    accuracy_m: float | None
    battery_percent: int | None
    network_state: str | None
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
    recipients: list[RecipientStatusOut]


class InboxAlertOut(BaseModel):
    alert_id: str
    sender_name: str
    sender_email: EmailStr
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


class MessageOut(BaseModel):
    message: str


class AuditEventOut(BaseModel):
    event_type: str
    resource_id: str | None
    detail: str | None
    created_at: datetime
