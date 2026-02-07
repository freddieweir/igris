"""Database connection and migration tests."""

import json
from datetime import datetime, timezone

from igris.db.connection import get_connection
from igris.db.migrations import get_current_version, run_migrations, SCHEMA_VERSION


def test_connection_opens():
    with get_connection() as conn:
        row = conn.execute("SELECT 1").fetchone()
        assert row[0] == 1


def test_migrations_create_tables():
    with get_connection() as conn:
        run_migrations(conn)

        # Verify all tables exist
        tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert "yubikeys" in tables
        assert "sessions" in tables
        assert "audit_log" in tables
        assert "schema_version" in tables


def test_schema_version_tracks():
    with get_connection() as conn:
        assert get_current_version(conn) == 0
        run_migrations(conn)
        assert get_current_version(conn) == SCHEMA_VERSION


def test_idempotent_migrations():
    """Running migrations twice should not fail."""
    with get_connection() as conn:
        run_migrations(conn)
        run_migrations(conn)
        assert get_current_version(conn) == SCHEMA_VERSION


def test_yubikey_crud():
    with get_connection() as conn:
        run_migrations(conn)
        now = datetime.now(timezone.utc).isoformat()

        conn.execute(
            """INSERT INTO yubikeys (serial, nickname, public_key, credential_id, registered_at)
               VALUES (?, ?, ?, ?, ?)""",
            ("12345678", "primary-key", b"pubkey", b"credid", now),
        )

        row = conn.execute("SELECT * FROM yubikeys WHERE serial = ?", ("12345678",)).fetchone()
        assert row["serial"] == "12345678"
        assert row["nickname"] == "primary-key"
        assert row["is_active"] == 1


def test_session_crud():
    with get_connection() as conn:
        run_migrations(conn)
        now = datetime.now(timezone.utc).isoformat()

        conn.execute(
            """INSERT INTO yubikeys (serial, nickname, public_key, credential_id, registered_at)
               VALUES (?, ?, ?, ?, ?)""",
            ("12345678", "test-key", b"pk", b"cid", now),
        )
        conn.execute(
            """INSERT INTO sessions (session_id, yubikey_serial, created_at, expires_at, ip_address)
               VALUES (?, ?, ?, ?, ?)""",
            ("sess-001", "12345678", now, now, "192.168.1.100"),
        )

        row = conn.execute("SELECT * FROM sessions WHERE session_id = ?", ("sess-001",)).fetchone()
        assert row["yubikey_serial"] == "12345678"
        assert row["ip_address"] == "192.168.1.100"


def test_audit_log_crud():
    with get_connection() as conn:
        run_migrations(conn)
        now = datetime.now(timezone.utc).isoformat()
        details = json.dumps({"action": "test"})

        conn.execute(
            """INSERT INTO audit_log (timestamp, event_type, yubikey_serial, ip_address, details)
               VALUES (?, ?, ?, ?, ?)""",
            (now, "test_event", "12345678", "127.0.0.1", details),
        )

        row = conn.execute("SELECT * FROM audit_log WHERE event_type = ?", ("test_event",)).fetchone()
        assert row["yubikey_serial"] == "12345678"
        parsed = json.loads(row["details"])
        assert parsed["action"] == "test"


def test_foreign_key_enforcement():
    """Sessions should reference valid yubikey serials."""
    import sqlite3

    import pytest

    with get_connection() as conn:
        run_migrations(conn)
        now = datetime.now(timezone.utc).isoformat()

        with pytest.raises(sqlite3.IntegrityError):
            conn.execute(
                """INSERT INTO sessions (session_id, yubikey_serial, created_at, expires_at)
                   VALUES (?, ?, ?, ?)""",
                ("sess-bad", "nonexistent", now, now),
            )
