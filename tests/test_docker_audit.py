"""Tests for Docker audit logger."""

import json
import tempfile
from pathlib import Path

from igris.docker.audit import _mask_serial, log_entry


class TestMaskSerial:
    def test_masks_serial(self):
        assert _mask_serial("12345678") == "******78"

    def test_short_serial(self):
        assert _mask_serial("12") == "******12"

    def test_unknown_passthrough(self):
        assert _mask_serial("unknown") == "unknown"
        assert _mask_serial("n/a") == "n/a"

    def test_empty_passthrough(self):
        assert _mask_serial("") == ""


class TestLogEntry:
    def test_creates_jsonl_entry(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            audit_path = Path(tmpdir) / "audit.jsonl"

            log_entry(
                operation="container.exec",
                auth_level="dual_tap",
                outcome="approved",
                raw_command="docker exec c1 bash",
                serial="12345678",
                audit_path=audit_path,
            )

            assert audit_path.exists()
            lines = audit_path.read_text().strip().splitlines()
            assert len(lines) == 1

            entry = json.loads(lines[0])
            assert entry["operation"] == "container.exec"
            assert entry["auth_level"] == "dual_tap"
            assert entry["outcome"] == "approved"
            assert entry["raw_command"] == "docker exec c1 bash"
            assert entry["serial"] == "******78"
            assert "timestamp" in entry
            assert "user" in entry
            assert "hostname" in entry

    def test_appends_multiple_entries(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            audit_path = Path(tmpdir) / "audit.jsonl"

            log_entry("container.rm", "dual_tap", "denied", "docker rm c1", audit_path=audit_path)
            log_entry("container.list", "auto_approve", "approved", "docker ps", audit_path=audit_path)

            lines = audit_path.read_text().strip().splitlines()
            assert len(lines) == 2

    def test_creates_parent_directories(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            audit_path = Path(tmpdir) / "deep" / "nested" / "audit.jsonl"

            log_entry("info", "auto_approve", "approved", "docker info", audit_path=audit_path)

            assert audit_path.exists()
