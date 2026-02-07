"""Middleware tests."""

import pytest
from fastapi.testclient import TestClient

from igris.db.connection import get_connection
from igris.db.migrations import run_migrations
from igris.main import app


@pytest.fixture(autouse=True)
def _init_db():
    with get_connection() as conn:
        run_migrations(conn)


def test_subnet_filter_blocks_disallowed_ip(monkeypatch: pytest.MonkeyPatch):
    """Requests from outside allowed subnets should be rejected."""
    import igris.middleware.subnet_filter as sf

    # Override the conftest patch: block everything including "testclient"
    monkeypatch.setattr(sf, "_is_allowed", lambda ip: False)

    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 403
    assert "Forbidden" in response.json()["detail"]


def test_subnet_filter_allows_permitted_ip():
    """Requests from allowed IPs should pass (conftest patches testclient through)."""
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200


def test_audit_logger_records_api_calls():
    """API calls (except /health) should be recorded in audit_log."""
    client = TestClient(app)
    client.get("/keys/list")

    with get_connection() as conn:
        rows = conn.execute(
            "SELECT * FROM audit_log WHERE event_type = 'api_request'"
        ).fetchall()

    paths = [r["details"] for r in rows]
    assert any("/keys/list" in p for p in paths)


def test_audit_logger_skips_health():
    """Health endpoint should NOT be logged to avoid noise."""
    # Clear audit log
    with get_connection() as conn:
        conn.execute("DELETE FROM audit_log")

    client = TestClient(app)
    client.get("/health")

    with get_connection() as conn:
        rows = conn.execute(
            "SELECT * FROM audit_log WHERE event_type = 'api_request'"
        ).fetchall()

    health_entries = [r for r in rows if "/health" in r["details"]]
    assert len(health_entries) == 0
