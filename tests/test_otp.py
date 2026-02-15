"""OTP authentication tests."""

from datetime import datetime, timezone

import pytest
from starlette.testclient import TestClient

from igris.db.connection import get_connection
from igris.db.migrations import run_migrations, get_current_version, SCHEMA_VERSION
from igris.core.otp import (
    check_rate_limit,
    hash_password,
    record_failure,
    register_otp,
    verify_otp,
    verify_password,
    _failed_attempts,
)
from igris.core.session import create_session, validate_session
from igris.main import app


@pytest.fixture(autouse=True)
def _init_db():
    """Ensure migrations are applied before each test."""
    with get_connection() as conn:
        run_migrations(conn)


@pytest.fixture(autouse=True)
def _clear_rate_limits():
    """Reset rate limit state between tests."""
    _failed_attempts.clear()
    yield
    _failed_attempts.clear()


def _register_test_key(serial: str = "12345678"):
    """Insert a dummy yubikey for FK constraints."""
    now = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        conn.execute(
            """INSERT OR IGNORE INTO yubikeys (serial, nickname, public_key, credential_id, registered_at)
               VALUES (?, ?, ?, ?, ?)""",
            (serial, "test", b"pk", b"cid", now),
        )


# --- Schema migration tests ---


def test_migration_v2_creates_otp_table():
    """Migration v2 should create the otp_credentials table."""
    with get_connection() as conn:
        tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert "otp_credentials" in tables


def test_migration_v2_adds_auth_method_column():
    """Migration v2 should add auth_method column to sessions."""
    _register_test_key()
    with get_connection() as conn:
        now = datetime.now(timezone.utc).isoformat()
        conn.execute(
            """INSERT INTO sessions (session_id, yubikey_serial, created_at, expires_at, ip_address, auth_method)
               VALUES (?, ?, ?, ?, ?, ?)""",
            ("sess-test", "12345678", now, now, "127.0.0.1", "otp"),
        )
        row = conn.execute(
            "SELECT auth_method FROM sessions WHERE session_id = 'sess-test'"
        ).fetchone()
        assert row["auth_method"] == "otp"


def test_migration_v2_schema_version():
    """Schema version should be 2 after migrations."""
    assert SCHEMA_VERSION == 2
    with get_connection() as conn:
        assert get_current_version(conn) == 2


def test_migration_v2_idempotent():
    """Running migrations twice should not fail."""
    with get_connection() as conn:
        run_migrations(conn)
        run_migrations(conn)
        assert get_current_version(conn) == 2


# --- Password hashing tests ---


def test_hash_and_verify_password():
    pw = "test-password-long-enough"
    hashed = hash_password(pw)
    assert hashed != pw
    assert verify_password(pw, hashed) is True


def test_verify_wrong_password():
    hashed = hash_password("correct-password-here")
    assert verify_password("wrong-password-here", hashed) is False


# --- OTP registration tests ---


def test_register_otp_success():
    _register_test_key()
    cred_id = register_otp("12345678", "my-secure-otp-password")
    assert cred_id is not None
    assert cred_id > 0


def test_register_otp_nonexistent_key():
    with pytest.raises(KeyError, match="not registered"):
        register_otp("nonexistent", "my-secure-otp-password")


def test_register_otp_deactivates_previous():
    _register_test_key()
    cred1 = register_otp("12345678", "first-password-here")
    cred2 = register_otp("12345678", "second-password-here")

    assert cred2 > cred1

    # First credential should be deactivated
    with get_connection() as conn:
        row = conn.execute(
            "SELECT is_active FROM otp_credentials WHERE id = ?", (cred1,)
        ).fetchone()
        assert row["is_active"] == 0

        row = conn.execute(
            "SELECT is_active FROM otp_credentials WHERE id = ?", (cred2,)
        ).fetchone()
        assert row["is_active"] == 1


# --- OTP verification tests ---


def test_verify_otp_correct_password():
    _register_test_key()
    register_otp("12345678", "my-correct-password")

    serial = verify_otp("my-correct-password")
    assert serial == "12345678"


def test_verify_otp_wrong_password():
    _register_test_key()
    register_otp("12345678", "my-correct-password")

    serial = verify_otp("wrong-password-here")
    assert serial is None


def test_otp_session_has_otp_auth_method():
    """OTP sessions should have auth_method='otp'."""
    _register_test_key()
    session_id = create_session("12345678", auth_method="otp")

    result = validate_session(session_id)
    assert result is not None
    assert result["auth_method"] == "otp"


# --- OTP session TTL tests ---


def test_otp_session_ttl_shorter_than_fido2(monkeypatch):
    """OTP sessions should use the shorter OTP TTL."""
    import igris.config as config_module
    assert config_module.settings.otp_session_ttl_seconds < config_module.settings.session_ttl_seconds


# --- Rate limiting tests ---


def test_rate_limit_allows_initial_attempts():
    assert check_rate_limit("198.51.100.1") is True


def test_rate_limit_blocks_after_max_attempts(monkeypatch):
    import igris.config as config_module
    monkeypatch.setattr(config_module.settings, "otp_max_attempts", 3)

    for _ in range(3):
        record_failure("198.51.100.2")

    assert check_rate_limit("198.51.100.2") is False


def test_rate_limit_different_ips_independent(monkeypatch):
    import igris.config as config_module
    monkeypatch.setattr(config_module.settings, "otp_max_attempts", 2)

    record_failure("198.51.100.3")
    record_failure("198.51.100.3")

    assert check_rate_limit("198.51.100.3") is False
    assert check_rate_limit("198.51.100.4") is True


# --- API endpoint integration tests ---


@pytest.fixture
def client():
    return TestClient(app)


def test_otp_register_endpoint(client):
    _register_test_key()
    resp = client.post(
        "/auth/otp/register",
        json={"yubikey_serial": "12345678", "password": "my-long-secure-password"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["yubikey_serial"] == "12345678"
    assert "credential_id" in data


def test_otp_register_short_password(client):
    _register_test_key()
    resp = client.post(
        "/auth/otp/register",
        json={"yubikey_serial": "12345678", "password": "short"},
    )
    assert resp.status_code == 422  # Validation error


def test_otp_register_nonexistent_key(client):
    resp = client.post(
        "/auth/otp/register",
        json={"yubikey_serial": "nonexistent", "password": "long-enough-password"},
    )
    assert resp.status_code == 404


def test_otp_verify_endpoint(client):
    _register_test_key()
    # First register
    client.post(
        "/auth/otp/register",
        json={"yubikey_serial": "12345678", "password": "my-long-secure-password"},
    )
    # Then verify
    resp = client.post(
        "/auth/otp/verify",
        json={"password": "my-long-secure-password"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["yubikey_serial"] == "12345678"
    assert data["auth_method"] == "otp"
    assert "session_id" in data


def test_otp_verify_wrong_password(client):
    _register_test_key()
    client.post(
        "/auth/otp/register",
        json={"yubikey_serial": "12345678", "password": "my-long-secure-password"},
    )
    resp = client.post(
        "/auth/otp/verify",
        json={"password": "wrong-password-here"},
    )
    assert resp.status_code == 401


def test_otp_verify_rate_limited(client, monkeypatch):
    import igris.config as config_module
    monkeypatch.setattr(config_module.settings, "otp_max_attempts", 2)

    _register_test_key()
    client.post(
        "/auth/otp/register",
        json={"yubikey_serial": "12345678", "password": "my-long-secure-password"},
    )

    # Exhaust attempts
    for _ in range(2):
        client.post("/auth/otp/verify", json={"password": "wrong"})

    # Next attempt should be rate limited
    resp = client.post("/auth/otp/verify", json={"password": "my-long-secure-password"})
    assert resp.status_code == 429


def test_session_validate_includes_auth_method(client):
    """Session validate endpoint should return auth_method."""
    _register_test_key()
    # Register and verify via OTP
    client.post(
        "/auth/otp/register",
        json={"yubikey_serial": "12345678", "password": "my-long-secure-password"},
    )
    resp = client.post(
        "/auth/otp/verify",
        json={"password": "my-long-secure-password"},
    )
    session_id = resp.json()["session_id"]

    # Validate session
    resp = client.get(f"/session/validate/{session_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["valid"] is True
    assert data["auth_method"] == "otp"
