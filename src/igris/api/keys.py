"""YubiKey registration and management endpoints."""

import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from igris.core.fido2 import begin_registration, complete_registration
from igris.db.connection import get_connection

router = APIRouter(prefix="/keys", tags=["keys"])

# In-memory challenge state for registration
_pending_reg_states: dict[str, dict] = {}


class RegisterBeginRequest(BaseModel):
    serial: str
    nickname: str = ""


class RegisterBeginResponse(BaseModel):
    request_id: str
    options: dict


class RegisterCompleteRequest(BaseModel):
    request_id: str
    response: dict


class RegisterCompleteResponse(BaseModel):
    serial: str
    nickname: str


class KeyInfo(BaseModel):
    serial: str
    nickname: str
    permissions: str
    registered_at: str
    last_used_at: str | None
    is_active: bool


@router.post("/register/begin", response_model=RegisterBeginResponse)
async def register_begin(body: RegisterBeginRequest):
    """Begin a FIDO2 key registration ceremony."""
    # Check if serial already registered
    with get_connection() as conn:
        existing = conn.execute(
            "SELECT serial FROM yubikeys WHERE serial = ?", (body.serial,)
        ).fetchone()
    if existing:
        raise HTTPException(status_code=409, detail=f"Key {body.serial} already registered")

    challenge = begin_registration(body.serial)

    request_id = secrets.token_urlsafe(16)
    _pending_reg_states[request_id] = {
        "state": challenge.state,
        "serial": body.serial,
        "nickname": body.nickname or f"key-{body.serial[:8]}",
    }

    return RegisterBeginResponse(
        request_id=request_id,
        options=_serialize_options(challenge.options),
    )


@router.post("/register/complete", response_model=RegisterCompleteResponse)
async def register_complete(body: RegisterCompleteRequest):
    """Complete a FIDO2 key registration ceremony."""
    pending = _pending_reg_states.pop(body.request_id, None)
    if pending is None:
        raise HTTPException(status_code=400, detail="Invalid or expired request_id")

    try:
        credential = complete_registration(pending["state"], body.response)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Registration failed: {e}")

    now = datetime.now(timezone.utc).isoformat()

    # Store the full AttestedCredentialData bytes for later authentication
    from fido2 import cbor
    cred_bytes = bytes(credential)

    with get_connection() as conn:
        conn.execute(
            """INSERT INTO yubikeys (serial, nickname, public_key, credential_id, registered_at)
               VALUES (?, ?, ?, ?, ?)""",
            (
                pending["serial"],
                pending["nickname"],
                cred_bytes,
                credential.credential_id,
                now,
            ),
        )

    return RegisterCompleteResponse(
        serial=pending["serial"],
        nickname=pending["nickname"],
    )


@router.get("/list", response_model=list[KeyInfo])
async def list_keys():
    """List all registered YubiKeys."""
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT serial, nickname, permissions, registered_at, last_used_at, is_active FROM yubikeys"
        ).fetchall()

    return [
        KeyInfo(
            serial=row["serial"],
            nickname=row["nickname"],
            permissions=row["permissions"],
            registered_at=row["registered_at"],
            last_used_at=row["last_used_at"],
            is_active=bool(row["is_active"]),
        )
        for row in rows
    ]


def _serialize_options(options: dict) -> dict:
    """Convert fido2 options to JSON-safe dict."""
    import base64

    def _convert(obj):
        if isinstance(obj, bytes):
            return base64.urlsafe_b64encode(obj).rstrip(b"=").decode()
        if isinstance(obj, dict):
            return {k: _convert(v) for k, v in obj.items()}
        if isinstance(obj, (list, tuple)):
            return [_convert(v) for v in obj]
        if hasattr(obj, "__dict__"):
            return {k: _convert(v) for k, v in vars(obj).items() if not k.startswith("_")}
        return obj

    return _convert(options)
