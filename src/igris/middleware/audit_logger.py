"""Audit logging middleware — log all API requests."""

import json
import logging
import time
from datetime import datetime, timezone

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from igris.db.connection import get_connection

logger = logging.getLogger(__name__)


class AuditLoggerMiddleware(BaseHTTPMiddleware):
    """Log every API request to the audit_log table."""

    async def dispatch(self, request: Request, call_next):
        start = time.monotonic()
        response = await call_next(request)
        duration_ms = round((time.monotonic() - start) * 1000, 1)

        client_ip = request.client.host if request.client else "unknown"
        details = {
            "method": request.method,
            "path": request.url.path,
            "status": response.status_code,
            "duration_ms": duration_ms,
        }

        # Skip logging health checks to avoid noise
        if request.url.path == "/health":
            return response

        try:
            with get_connection() as conn:
                conn.execute(
                    """INSERT INTO audit_log (timestamp, event_type, yubikey_serial, ip_address, details)
                       VALUES (?, ?, ?, ?, ?)""",
                    (
                        datetime.now(timezone.utc).isoformat(),
                        "api_request",
                        "",
                        client_ip,
                        json.dumps(details),
                    ),
                )
        except Exception:
            logger.exception("Failed to write audit log")

        return response
