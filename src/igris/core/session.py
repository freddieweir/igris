"""Session management — create, validate, expire."""

import json
import logging
import secrets
from datetime import datetime, timedelta, timezone

import igris.config as _config
from igris.db.connection import get_connection

logger = logging.getLogger(__name__)


def create_session(yubikey_serial: str, ip_address: str = "", tier: str = "standard", auth_method: str = "fido2") -> str:
    """Create a new authenticated session. Returns session_id."""
    session_id = secrets.token_urlsafe(32)
    now = datetime.now(timezone.utc)

    # Dynamic TTL based on auth method
    if auth_method == "otp":
        ttl = _config.settings.otp_session_ttl_seconds
    else:
        ttl = _config.settings.session_ttl_seconds
    expires = now + timedelta(seconds=ttl)

    with get_connection() as conn:
        conn.execute(
            """INSERT INTO sessions (session_id, yubikey_serial, created_at, expires_at, tier_level, ip_address, auth_method)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (session_id, yubikey_serial, now.isoformat(), expires.isoformat(), tier, ip_address, auth_method),
        )
        _audit(conn, "session_created", yubikey_serial, ip_address, {"session_id": session_id, "auth_method": auth_method})

    logger.info("Session created: %s for serial=%s (auth=%s)", session_id[:8], yubikey_serial, auth_method)
    return session_id


def validate_session(session_id: str) -> dict | None:
    """Validate a session. Returns session data if valid, None if expired/missing."""
    now = datetime.now(timezone.utc)

    with get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM sessions WHERE session_id = ?", (session_id,)
        ).fetchone()

        if row is None:
            return None

        expires_at = datetime.fromisoformat(row["expires_at"])
        if expires_at < now:
            conn.execute("DELETE FROM sessions WHERE session_id = ?", (session_id,))
            _audit(conn, "session_expired", row["yubikey_serial"], row["ip_address"], {"session_id": session_id})
            return None

        return dict(row)


def expire_session(session_id: str) -> bool:
    """Manually expire/revoke a session. Returns True if session existed."""
    with get_connection() as conn:
        row = conn.execute(
            "SELECT yubikey_serial, ip_address FROM sessions WHERE session_id = ?", (session_id,)
        ).fetchone()

        if row is None:
            return False

        conn.execute("DELETE FROM sessions WHERE session_id = ?", (session_id,))
        _audit(conn, "session_revoked", row["yubikey_serial"], row["ip_address"], {"session_id": session_id})

    logger.info("Session revoked: %s", session_id[:8])
    return True


def cleanup_expired() -> int:
    """Remove all expired sessions. Returns count of removed sessions."""
    now = datetime.now(timezone.utc).isoformat()

    with get_connection() as conn:
        cursor = conn.execute("DELETE FROM sessions WHERE expires_at < ?", (now,))
        count = cursor.rowcount

    if count > 0:
        logger.info("Cleaned up %d expired sessions", count)
    return count


def _audit(conn, event_type: str, serial: str, ip: str, details: dict) -> None:
    """Write an audit log entry within an existing connection."""
    conn.execute(
        """INSERT INTO audit_log (timestamp, event_type, yubikey_serial, ip_address, details)
           VALUES (?, ?, ?, ?, ?)""",
        (datetime.now(timezone.utc).isoformat(), event_type, serial, ip, json.dumps(details)),
    )
