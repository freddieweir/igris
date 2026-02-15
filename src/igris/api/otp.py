"""OTP authentication endpoints for YubiKey long-tap / static password."""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, field_validator

from igris.core.otp import check_rate_limit, record_failure, register_otp, verify_otp
from igris.core.session import create_session

router = APIRouter(prefix="/auth/otp", tags=["otp"])


class OTPVerifyRequest(BaseModel):
    password: str

    @field_validator("password")
    @classmethod
    def password_not_empty(cls, v: str) -> str:
        if not v:
            raise ValueError("Password must not be empty")
        return v


class OTPVerifyResponse(BaseModel):
    session_id: str
    yubikey_serial: str
    auth_method: str = "otp"


class OTPRegisterRequest(BaseModel):
    yubikey_serial: str
    password: str

    @field_validator("password")
    @classmethod
    def password_min_length(cls, v: str) -> str:
        if len(v) < 12:
            raise ValueError("Password must be at least 12 characters")
        return v


class OTPRegisterResponse(BaseModel):
    yubikey_serial: str
    credential_id: int


@router.post("/verify", response_model=OTPVerifyResponse)
async def otp_verify(body: OTPVerifyRequest, request: Request):
    """Verify a YubiKey OTP / static password."""
    client_ip = request.client.host if request.client else ""

    if not check_rate_limit(client_ip):
        raise HTTPException(status_code=429, detail="Too many failed attempts, try again later")

    serial = verify_otp(body.password)
    if serial is None:
        record_failure(client_ip)
        raise HTTPException(status_code=401, detail="Invalid OTP")

    session_id = create_session(serial, ip_address=client_ip, auth_method="otp")
    return OTPVerifyResponse(session_id=session_id, yubikey_serial=serial)


@router.post("/register", response_model=OTPRegisterResponse)
async def otp_register(body: OTPRegisterRequest):
    """Register an OTP credential for a YubiKey."""
    try:
        credential_id = register_otp(body.yubikey_serial, body.password)
    except KeyError:
        raise HTTPException(status_code=404, detail=f"YubiKey {body.yubikey_serial} not registered")

    return OTPRegisterResponse(
        yubikey_serial=body.yubikey_serial,
        credential_id=credential_id,
    )
