"""OTP password hashing, verification, and rate limiting."""

import logging
import time
from collections import defaultdict
from datetime import datetime, timezone

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

import igris.config as _config
from igris.db.connection import get_connection

logger = logging.getLogger(__name__)

_hasher = PasswordHasher()

# In-memory rate limiting (consistent with existing challenge state pattern).
# Note: resets on process restart; single-worker only.
_failed_attempts: dict[str, list[float]] = defaultdict(list)


def hash_password(password: str) -> str:
    """Hash a password using Argon2id."""
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    """Verify a password against an Argon2id hash."""
    try:
        return _hasher.verify(password_hash, password)
    except VerifyMismatchError:
        return False


def check_rate_limit(ip: str) -> bool:
    """Return True if the IP is allowed to attempt, False if locked out."""
    now = time.monotonic()
    window = _config.settings.otp_lockout_seconds
    max_attempts = _config.settings.otp_max_attempts

    # Prune old entries outside the window
    _failed_attempts[ip] = [t for t in _failed_attempts[ip] if now - t < window]

    return len(_failed_attempts[ip]) < max_attempts


def record_failure(ip: str) -> None:
    """Record a failed OTP attempt for rate limiting."""
    _failed_attempts[ip].append(time.monotonic())


def register_otp(serial: str, password: str) -> int:
    """Store an OTP credential for a YubiKey serial.

    Deactivates any previous OTP credentials for the same serial.
    Returns the new credential ID.
    """
    password_hash = hash_password(password)
    now = datetime.now(timezone.utc).isoformat()

    with get_connection() as conn:
        # Verify the yubikey exists
        row = conn.execute(
            "SELECT serial FROM yubikeys WHERE serial = ?", (serial,)
        ).fetchone()
        if row is None:
            raise KeyError(f"YubiKey serial {serial} not registered")

        # Deactivate previous OTP credentials for this serial
        conn.execute(
            "UPDATE otp_credentials SET is_active = 0 WHERE yubikey_serial = ?",
            (serial,),
        )

        # Insert new credential
        cursor = conn.execute(
            """INSERT INTO otp_credentials
               (yubikey_serial, password_hash, hash_algorithm, created_at, is_active)
               VALUES (?, ?, 'argon2id', ?, 1)""",
            (serial, password_hash, now),
        )
        credential_id = cursor.lastrowid

        # Audit
        conn.execute(
            """INSERT INTO audit_log (timestamp, event_type, yubikey_serial, ip_address, details)
               VALUES (?, 'otp_registered', ?, '', '{}')""",
            (now, serial),
        )

    logger.info("OTP credential registered for serial=%s (id=%d)", serial, credential_id)
    return credential_id


def verify_otp(password: str) -> str | None:
    """Check password against all active OTP credentials.

    Returns the matching YubiKey serial, or None if no match.
    """
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT yubikey_serial, password_hash FROM otp_credentials WHERE is_active = 1"
        ).fetchall()

    for row in rows:
        if verify_password(password, row["password_hash"]):
            return row["yubikey_serial"]

    return None
