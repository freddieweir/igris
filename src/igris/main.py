"""FastAPI application entry point."""

import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI

from igris import __version__
from igris.api.auth import router as auth_router
from igris.api.audit import router as audit_router
from igris.api.otp import router as otp_router
from igris.api.keys import router as keys_router
from igris.api.sessions import router as sessions_router
from igris.db.connection import get_connection
from igris.db.migrations import run_migrations
from igris.middleware.audit_logger import AuditLoggerMiddleware
from igris.middleware.subnet_filter import SubnetFilterMiddleware

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Run database migrations on startup."""
    with get_connection() as conn:
        version = run_migrations(conn)
        logger.info("Database ready at schema version %d", version)
    yield


app = FastAPI(
    title="Igris",
    description="YubiKey FIDO2 authentication service",
    version=__version__,
    docs_url="/docs",
    redoc_url=None,
    lifespan=lifespan,
)

# Middleware (order matters: outermost first)
app.add_middleware(AuditLoggerMiddleware)
app.add_middleware(SubnetFilterMiddleware)

# Routers
app.include_router(auth_router)
app.include_router(otp_router)
app.include_router(keys_router)
app.include_router(sessions_router)
app.include_router(audit_router)


@app.get("/health")
async def health() -> dict:
    """Health check endpoint."""
    return {
        "status": "healthy",
        "version": __version__,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
