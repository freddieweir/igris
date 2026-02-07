"""Audit log endpoints."""

from fastapi import APIRouter, Query
from pydantic import BaseModel

from igris.db.connection import get_connection

router = APIRouter(prefix="/audit", tags=["audit"])


class AuditLogEntry(BaseModel):
    id: int
    timestamp: str
    event_type: str
    yubikey_serial: str
    ip_address: str
    details: str


@router.get("/log", response_model=list[AuditLogEntry])
async def get_audit_log(
    limit: int = Query(default=100, ge=1, le=1000),
    event_type: str | None = Query(default=None),
):
    """Retrieve audit log entries, newest first."""
    with get_connection() as conn:
        if event_type:
            rows = conn.execute(
                "SELECT * FROM audit_log WHERE event_type = ? ORDER BY id DESC LIMIT ?",
                (event_type, limit),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM audit_log ORDER BY id DESC LIMIT ?",
                (limit,),
            ).fetchall()

    return [
        AuditLogEntry(
            id=row["id"],
            timestamp=row["timestamp"],
            event_type=row["event_type"],
            yubikey_serial=row["yubikey_serial"],
            ip_address=row["ip_address"],
            details=row["details"],
        )
        for row in rows
    ]
