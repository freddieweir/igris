"""Schema migrations with version tracking."""

import logging
import sqlite3

logger = logging.getLogger(__name__)

SCHEMA_VERSION = 2

MIGRATIONS: dict[int, list[str]] = {
    1: [
        """
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS yubikeys (
            serial TEXT PRIMARY KEY,
            nickname TEXT NOT NULL,
            public_key BLOB NOT NULL,
            credential_id BLOB NOT NULL,
            permissions TEXT NOT NULL DEFAULT 'standard',
            registered_at TEXT NOT NULL,
            last_used_at TEXT,
            is_active INTEGER NOT NULL DEFAULT 1
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS sessions (
            session_id TEXT PRIMARY KEY,
            yubikey_serial TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            tier_level TEXT NOT NULL DEFAULT 'standard',
            ip_address TEXT NOT NULL DEFAULT '',
            FOREIGN KEY (yubikey_serial) REFERENCES yubikeys(serial)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            event_type TEXT NOT NULL,
            yubikey_serial TEXT NOT NULL DEFAULT '',
            ip_address TEXT NOT NULL DEFAULT '',
            details TEXT NOT NULL DEFAULT '{}'
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_sessions_expires
        ON sessions(expires_at)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_audit_timestamp
        ON audit_log(timestamp)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_audit_event_type
        ON audit_log(event_type)
        """,
    ],
    2: [
        """
        CREATE TABLE IF NOT EXISTS otp_credentials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            yubikey_serial TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            hash_algorithm TEXT NOT NULL DEFAULT 'argon2id',
            created_at TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            FOREIGN KEY (yubikey_serial) REFERENCES yubikeys(serial)
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_otp_creds_serial
        ON otp_credentials(yubikey_serial)
        """,
        """
        ALTER TABLE sessions ADD COLUMN auth_method TEXT NOT NULL DEFAULT 'fido2'
        """,
    ],
}


def get_current_version(conn: sqlite3.Connection) -> int:
    """Get current schema version, or 0 if uninitialized."""
    try:
        row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
        return row[0] if row and row[0] is not None else 0
    except sqlite3.OperationalError:
        return 0


def run_migrations(conn: sqlite3.Connection) -> int:
    """Apply pending migrations. Returns the final schema version."""
    current = get_current_version(conn)

    if current >= SCHEMA_VERSION:
        logger.debug("Database schema is up to date (version %d)", current)
        return current

    for version in range(current + 1, SCHEMA_VERSION + 1):
        if version not in MIGRATIONS:
            raise RuntimeError(f"Missing migration for version {version}")

        logger.info("Applying migration v%d", version)
        for statement in MIGRATIONS[version]:
            conn.execute(statement)

        conn.execute("INSERT INTO schema_version (version) VALUES (?)", (version,))

    conn.commit()
    logger.info("Database migrated to version %d", SCHEMA_VERSION)
    return SCHEMA_VERSION
