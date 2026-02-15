"""FIDO2 authentication endpoints."""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from igris.core.fido2 import (
    begin_authentication,
    complete_authentication,
)
from igris.core.session import create_session
from igris.db.connection import get_connection
from igris.api.utils import serialize_fido2_options
from fido2.webauthn import AttestedCredentialData

router = APIRouter(prefix="/auth/fido2", tags=["auth"])

# In-memory challenge state (per-session; production would use Redis/DB)
_pending_auth_states: dict[str, dict] = {}


class AuthBeginResponse(BaseModel):
    request_id: str
    options: dict


class AuthCompleteRequest(BaseModel):
    request_id: str
    response: dict


class AuthCompleteResponse(BaseModel):
    session_id: str
    yubikey_serial: str


@router.post("/begin", response_model=AuthBeginResponse)
async def auth_begin():
    """Begin a FIDO2 authentication ceremony."""
    credentials = _load_all_credentials()
    if not credentials:
        raise HTTPException(status_code=404, detail="No registered keys found")

    challenge = begin_authentication(credentials)

    import secrets
    request_id = secrets.token_urlsafe(16)
    _pending_auth_states[request_id] = {
        "state": challenge.state,
        "credentials": credentials,
    }

    return AuthBeginResponse(
        request_id=request_id,
        options=serialize_fido2_options(challenge.options),
    )


@router.post("/complete", response_model=AuthCompleteResponse)
async def auth_complete(body: AuthCompleteRequest, request: Request):
    """Complete a FIDO2 authentication ceremony."""
    pending = _pending_auth_states.pop(body.request_id, None)
    if pending is None:
        raise HTTPException(status_code=400, detail="Invalid or expired request_id")

    try:
        matched = complete_authentication(
            state=pending["state"],
            credentials=pending["credentials"],
            response=body.response,
        )
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Authentication failed: {e}")

    # Find the serial for the matched credential
    serial = _find_serial_by_credential(matched.credential_id)
    if serial is None:
        raise HTTPException(status_code=500, detail="Credential matched but serial not found")

    # Update last_used_at
    from datetime import datetime, timezone
    with get_connection() as conn:
        conn.execute(
            "UPDATE yubikeys SET last_used_at = ? WHERE serial = ?",
            (datetime.now(timezone.utc).isoformat(), serial),
        )

    client_ip = request.client.host if request.client else ""
    session_id = create_session(serial, ip_address=client_ip)

    return AuthCompleteResponse(session_id=session_id, yubikey_serial=serial)


def _load_all_credentials() -> list[AttestedCredentialData]:
    """Load all active registered credentials from the database."""
    from fido2.webauthn import AttestedCredentialData

    with get_connection() as conn:
        rows = conn.execute(
            "SELECT public_key, credential_id FROM yubikeys WHERE is_active = 1"
        ).fetchall()

    credentials = []
    for row in rows:
        try:
            cred = AttestedCredentialData(row["public_key"])
            credentials.append(cred)
        except Exception:
            pass
    return credentials


def _find_serial_by_credential(credential_id: bytes) -> str | None:
    """Look up the yubikey serial for a given credential_id."""
    with get_connection() as conn:
        row = conn.execute(
            "SELECT serial FROM yubikeys WHERE credential_id = ? AND is_active = 1",
            (credential_id,),
        ).fetchone()
    return row["serial"] if row else None
