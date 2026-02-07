#!/usr/bin/env python3
"""Initialize the igris database (first-boot setup)."""

import sys
from pathlib import Path

# Allow running from scripts/ directory
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from igris.db.connection import get_connection
from igris.db.migrations import run_migrations


def main() -> int:
    with get_connection() as conn:
        version = run_migrations(conn)
        print(f"Database initialized at schema version {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
