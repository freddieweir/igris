"""Session management endpoints."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from igris.core.session import validate_session, expire_session

router = APIRouter(prefix="/session", tags=["sessions"])


class SessionValidateResponse(BaseModel):
    valid: bool
    yubikey_serial: str | None = None
    tier_level: str | None = None
    expires_at: str | None = None


class SessionRevokeResponse(BaseModel):
    revoked: bool


@router.get("/validate/{session_id}", response_model=SessionValidateResponse)
async def validate(session_id: str):
    """Check if a session is valid."""
    result = validate_session(session_id)
    if result is None:
        return SessionValidateResponse(valid=False)

    return SessionValidateResponse(
        valid=True,
        yubikey_serial=result["yubikey_serial"],
        tier_level=result["tier_level"],
        expires_at=result["expires_at"],
    )


@router.delete("/revoke/{session_id}", response_model=SessionRevokeResponse)
async def revoke(session_id: str):
    """Revoke an active session."""
    revoked = expire_session(session_id)
    return SessionRevokeResponse(revoked=revoked)
