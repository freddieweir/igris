"""FastAPI application entry point."""

from datetime import datetime, timezone

from fastapi import FastAPI

from igris import __version__

app = FastAPI(
    title="Igris",
    description="YubiKey FIDO2 authentication service",
    version=__version__,
    docs_url="/docs",
    redoc_url=None,
)


@app.get("/health")
async def health() -> dict:
    """Health check endpoint."""
    return {
        "status": "healthy",
        "version": __version__,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
