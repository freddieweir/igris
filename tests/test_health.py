"""Health endpoint tests."""

from fastapi.testclient import TestClient

from igris.main import app

client = TestClient(app)


def test_health_returns_200():
    response = client.get("/health")
    assert response.status_code == 200


def test_health_response_shape():
    response = client.get("/health")
    data = response.json()
    assert data["status"] == "healthy"
    assert "version" in data
    assert "timestamp" in data
