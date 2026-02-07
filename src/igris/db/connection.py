"""Database connection manager with optional sqlcipher encryption."""

import logging
import secrets
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Generator

import igris.config as _config

logger = logging.getLogger(__name__)

# Try sqlcipher; fall back to standard sqlite3 for local dev
try:
    from pysqlcipher3 import dbapi2 as sqlcipher  # type: ignore[import-untyped]

    ENCRYPTION_AVAILABLE = True
except ImportError:
    sqlcipher = None
    ENCRYPTION_AVAILABLE = False


def _get_or_create_master_key() -> str:
    """Load master key from file, or generate one on first boot."""
    key_path = _config.settings.db_master_key_path
    if key_path.exists():
        return key_path.read_text().strip()

    key_path.parent.mkdir(parents=True, exist_ok=True)
    key = secrets.token_hex(32)
    key_path.write_text(key)
    key_path.chmod(0o600)
    logger.info("Generated new database master key at %s", key_path)
    return key


def _open_connection(db_path: Path) -> sqlite3.Connection:
    """Open a database connection with encryption if available."""
    db_path.parent.mkdir(parents=True, exist_ok=True)

    if ENCRYPTION_AVAILABLE and sqlcipher is not None:
        conn = sqlcipher.connect(str(db_path))
        master_key = _get_or_create_master_key()
        conn.execute(f"PRAGMA key='{master_key}'")
        logger.debug("Opened encrypted database at %s", db_path)
    else:
        conn = sqlite3.connect(str(db_path))
        logger.debug("Opened unencrypted database at %s (sqlcipher not available)", db_path)

    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def get_connection() -> Generator[sqlite3.Connection, None, None]:
    """Context manager that yields a database connection."""
    conn = _open_connection(_config.settings.db_path_resolved)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
