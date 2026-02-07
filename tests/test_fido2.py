"""FIDO2 registration and authentication tests."""

from igris.core.fido2 import (
    begin_authentication,
    begin_registration,
    complete_authentication,
    complete_registration,
)
from tests.soft_authenticator import SoftAuthenticator

RP_ID = "igris.local"
ORIGIN = "https://igris.local:8920"


def _extract_challenge(options: dict) -> bytes:
    """Pull the raw challenge bytes from server options."""
    # Options structure: {publicKey: {challenge: bytes, ...}}
    pk = options.get("publicKey", options)
    return pk.challenge if hasattr(pk, "challenge") else pk["challenge"]


def test_begin_registration_returns_challenge():
    challenge = begin_registration("TEST-001")
    assert challenge.options is not None
    assert challenge.state is not None


def test_full_registration_flow():
    """Register a soft authenticator and verify credential is returned."""
    auth = SoftAuthenticator()
    challenge = begin_registration("TEST-001")

    raw_challenge = _extract_challenge(challenge.options)
    response = auth.make_credential(RP_ID, raw_challenge, ORIGIN)

    credential = complete_registration(challenge.state, response)
    assert credential is not None
    assert credential.credential_id == auth.credential_id


def test_full_authentication_flow():
    """Register then authenticate with a soft authenticator."""
    auth = SoftAuthenticator()

    # Register
    reg_challenge = begin_registration("TEST-001")
    raw_challenge_reg = _extract_challenge(reg_challenge.options)
    response_reg = auth.make_credential(RP_ID, raw_challenge_reg, ORIGIN)
    credential = complete_registration(reg_challenge.state, response_reg)

    # Authenticate
    auth_challenge = begin_authentication([credential])
    assert auth_challenge.options is not None

    raw_challenge_auth = _extract_challenge(auth_challenge.options)
    response_auth = auth.get_assertion(RP_ID, raw_challenge_auth, ORIGIN)

    result = complete_authentication(auth_challenge.state, [credential], response_auth)
    assert result is not None
