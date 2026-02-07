"""API endpoint tests."""

from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from igris.db.connection import get_connection
from igris.db.migrations import run_migrations
from igris.main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def _init_db():
    """Ensure migrations are applied before each test."""
    with get_connection() as conn:
        run_migrations(conn)


# --- Health ---

def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"


# --- Keys ---

def test_list_keys_empty():
    response = client.get("/keys/list")
    assert response.status_code == 200
    assert response.json() == []


def test_register_begin():
    response = client.post(
        "/keys/register/begin",
        json={"serial": "TEST-001", "nickname": "test-key"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "request_id" in data
    assert "options" in data


def test_register_duplicate_serial():
    """Registering the same serial twice should fail."""
    now = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        conn.execute(
            """INSERT INTO yubikeys (serial, nickname, public_key, credential_id, registered_at)
               VALUES (?, ?, ?, ?, ?)""",
            ("DUPE-001", "existing", b"pk", b"cid", now),
        )

    response = client.post(
        "/keys/register/begin",
        json={"serial": "DUPE-001"},
    )
    assert response.status_code == 409


def test_list_keys_after_insert():
    now = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        conn.execute(
            """INSERT INTO yubikeys (serial, nickname, public_key, credential_id, registered_at)
               VALUES (?, ?, ?, ?, ?)""",
            ("LIST-001", "my-key", b"pk", b"cid", now),
        )

    response = client.get("/keys/list")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["serial"] == "LIST-001"
    assert data[0]["nickname"] == "my-key"


# --- Sessions ---

def test_validate_invalid_session():
    response = client.get("/session/validate/nonexistent-id")
    assert response.status_code == 200
    data = response.json()
    assert data["valid"] is False


def test_session_lifecycle():
    """Create a session via the core module, then validate and revoke via API."""
    from igris.core.session import create_session

    now = datetime.now(timezone.utc).isoformat()
    with get_connection() as conn:
        conn.execute(
            """INSERT INTO yubikeys (serial, nickname, public_key, credential_id, registered_at)
               VALUES (?, ?, ?, ?, ?)""",
            ("SESS-001", "test", b"pk", b"cid", now),
        )

    session_id = create_session("SESS-001", ip_address="127.0.0.1")

    # Validate
    response = client.get(f"/session/validate/{session_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["valid"] is True
    assert data["yubikey_serial"] == "SESS-001"

    # Revoke
    response = client.delete(f"/session/revoke/{session_id}")
    assert response.status_code == 200
    assert response.json()["revoked"] is True

    # Validate again — should be invalid
    response = client.get(f"/session/validate/{session_id}")
    assert response.json()["valid"] is False


# --- Auth ---

def test_auth_begin_no_keys():
    """Auth begin should fail when no keys are registered."""
    response = client.post("/auth/fido2/begin")
    assert response.status_code == 404


def test_auth_complete_bad_request_id():
    response = client.post(
        "/auth/fido2/complete",
        json={"request_id": "fake", "response": {}},
    )
    assert response.status_code == 400


# --- Audit ---

def test_audit_log_empty():
    response = client.get("/audit/log")
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_audit_log_with_filter():
    with get_connection() as conn:
        conn.execute(
            """INSERT INTO audit_log (timestamp, event_type, yubikey_serial, ip_address, details)
               VALUES (?, ?, ?, ?, ?)""",
            (datetime.now(timezone.utc).isoformat(), "test_event", "TEST", "127.0.0.1", "{}"),
        )

    response = client.get("/audit/log?event_type=test_event")
    assert response.status_code == 200
    data = response.json()
    assert any(e["event_type"] == "test_event" for e in data)
