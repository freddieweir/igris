"""Database model dataclasses."""

from dataclasses import dataclass, field
from datetime import datetime, timezone


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class YubiKey:
    serial: str
    nickname: str
    public_key: bytes
    credential_id: bytes
    permissions: str = "standard"
    registered_at: datetime = field(default_factory=_utcnow)
    last_used_at: datetime | None = None
    is_active: bool = True


@dataclass
class Session:
    session_id: str
    yubikey_serial: str
    created_at: datetime = field(default_factory=_utcnow)
    expires_at: datetime = field(default_factory=_utcnow)
    tier_level: str = "standard"
    ip_address: str = ""
    auth_method: str = "fido2"


@dataclass
class AuditEntry:
    id: int | None = None
    timestamp: datetime = field(default_factory=_utcnow)
    event_type: str = ""
    yubikey_serial: str = ""
    ip_address: str = ""
    details: str = ""  # JSON string


@dataclass
class OTPCredential:
    id: int | None = None
    yubikey_serial: str = ""
    password_hash: str = ""
    hash_algorithm: str = "argon2id"
    created_at: datetime = field(default_factory=_utcnow)
    is_active: bool = True
