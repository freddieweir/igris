"""Session management tests."""

from datetime import datetime, timedelta, timezone

import pytest

from igris.db.connection import get_connection
from igris.db.migrations import run_migrations
from igris.core.session import (
    cleanup_expired,
    create_session,
    expire_session,
    validate_session,
)


@pytest.fixture(autouse=True)
def _init_db():
    """Ensure migrations are applied before each test."""
    with get_connection() as conn:
        run_migrations(conn)


def _register_test_key(serial: str = "12345678"):
    """Insert a dummy yubikey for FK constraints."""
    now = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        conn.execute(
            """INSERT OR IGNORE INTO yubikeys (serial, nickname, public_key, credential_id, registered_at)
               VALUES (?, ?, ?, ?, ?)""",
            (serial, "test", b"pk", b"cid", now),
        )


def test_create_and_validate_session():
    _register_test_key()
    session_id = create_session("12345678", ip_address="10.211.55.7")
    assert session_id is not None

    result = validate_session(session_id)
    assert result is not None
    assert result["yubikey_serial"] == "12345678"
    assert result["ip_address"] == "10.211.55.7"


def test_validate_nonexistent_session():
    assert validate_session("nonexistent") is None


def test_expire_session():
    _register_test_key()
    session_id = create_session("12345678")
    assert expire_session(session_id) is True
    assert validate_session(session_id) is None


def test_expire_nonexistent_session():
    assert expire_session("nonexistent") is False


def test_expired_session_auto_cleanup():
    """A session past its TTL should return None on validate."""
    _register_test_key()
    session_id = create_session("12345678")

    # Manually set expiry to the past
    past = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
    with get_connection() as conn:
        conn.execute(
            "UPDATE sessions SET expires_at = ? WHERE session_id = ?",
            (past, session_id),
        )

    assert validate_session(session_id) is None


def test_cleanup_expired_removes_old_sessions():
    _register_test_key()
    s1 = create_session("12345678")
    s2 = create_session("12345678")

    # Expire both
    past = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
    with get_connection() as conn:
        conn.execute("UPDATE sessions SET expires_at = ?", (past,))

    removed = cleanup_expired()
    assert removed == 2


def test_session_creates_audit_entry():
    _register_test_key()
    create_session("12345678", ip_address="10.0.0.1")

    with get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM audit_log WHERE event_type = 'session_created'"
        ).fetchone()
        assert row is not None
        assert row["yubikey_serial"] == "12345678"
        assert row["ip_address"] == "10.0.0.1"
