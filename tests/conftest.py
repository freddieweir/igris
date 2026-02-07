"""Shared test fixtures."""

from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def _isolate_db(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Point every test at a throwaway DB in tmp_path."""
    db_file = tmp_path / "test.db"
    key_file = tmp_path / ".test-key"
    monkeypatch.setenv("IGRIS_DB_PATH", str(db_file))
    monkeypatch.setenv("IGRIS_DB_MASTER_KEY_FILE", str(key_file))

    # Rebuild the settings singleton so the env vars take effect
    import igris.config as config_module
    fresh = config_module.Settings()
    monkeypatch.setattr(config_module, "settings", fresh)

    # Allow Starlette TestClient through subnet filter.
    # TestClient reports client IP as "testclient" (not a real IP),
    # so we patch _is_allowed to accept it during tests.
    import igris.middleware.subnet_filter as sf
    original = sf._is_allowed

    def _test_is_allowed(ip_str: str) -> bool:
        if ip_str == "testclient":
            return True
        return original(ip_str)

    monkeypatch.setattr(sf, "_is_allowed", _test_is_allowed)
