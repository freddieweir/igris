"""FastAPI application entry point."""

import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI

from igris import __version__
from igris.db.connection import get_connection
from igris.db.migrations import run_migrations

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


@app.get("/health")
async def health() -> dict:
    """Health check endpoint."""
    return {
        "status": "healthy",
        "version": __version__,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
