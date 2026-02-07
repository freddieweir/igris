"""Subnet filtering middleware — reject requests from outside allowed networks."""

import ipaddress
import logging

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

import igris.config as _config

logger = logging.getLogger(__name__)


class SubnetFilterMiddleware(BaseHTTPMiddleware):
    """Reject requests from IP addresses outside IGRIS_ALLOWED_SUBNETS."""

    async def dispatch(self, request: Request, call_next):
        client_ip = request.client.host if request.client else "unknown"

        if not _is_allowed(client_ip):
            logger.warning("Blocked request from %s", client_ip)
            return JSONResponse(
                status_code=403,
                content={"detail": "Forbidden: IP not in allowed subnets"},
            )

        return await call_next(request)


def _is_allowed(ip_str: str) -> bool:
    """Check if an IP address falls within any allowed subnet."""
    try:
        addr = ipaddress.ip_address(ip_str)
    except ValueError:
        return False

    for subnet_str in _config.settings.subnet_list:
        try:
            network = ipaddress.ip_network(subnet_str, strict=False)
            if addr in network:
                return True
        except ValueError:
            logger.error("Invalid subnet in config: %s", subnet_str)

    return False
