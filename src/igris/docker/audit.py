"""JSONL audit logger for Docker operations."""

from __future__ import annotations

import json
import os
import socket
from datetime import datetime, timezone
from pathlib import Path


def _mask_serial(serial: str) -> str:
    """Mask YubiKey serial, keeping last 2 digits."""
    if not serial or serial in ("unknown", "n/a"):
        return serial
    return f"******{serial[-2:]}"


def log_entry(
    operation: str,
    auth_level: str,
    outcome: str,
    raw_command: str,
    serial: str = "unknown",
    audit_path: Path | None = None,
) -> None:
    """Append a JSONL audit entry."""
    if audit_path is None:
        audit_path = Path.home() / ".cache" / "igris" / "audit.jsonl"

    audit_path.parent.mkdir(parents=True, exist_ok=True)

    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "operation": operation,
        "auth_level": auth_level,
        "outcome": outcome,
        "raw_command": raw_command,
        "user": os.environ.get("USER", "unknown"),
        "hostname": socket.gethostname(),
        "serial": _mask_serial(serial),
    }

    with open(audit_path, "a") as f:
        f.write(json.dumps(entry, separators=(",", ":")) + "\n")
