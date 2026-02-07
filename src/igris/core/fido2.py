"""FIDO2 registration and authentication logic."""

import logging
from dataclasses import dataclass

from fido2.server import Fido2Server
from fido2.webauthn import (
    AttestedCredentialData,
    PublicKeyCredentialRpEntity,
    PublicKeyCredentialUserEntity,
)

import igris.config as _config

logger = logging.getLogger(__name__)


@dataclass
class RegistrationChallenge:
    """Data returned from begin_registration."""
    options: dict
    state: dict


@dataclass
class AuthenticationChallenge:
    """Data returned from begin_authentication."""
    options: dict
    state: dict


def _get_server() -> Fido2Server:
    """Build a Fido2Server from current settings."""
    rp = PublicKeyCredentialRpEntity(
        id=_config.settings.rp_id,
        name=_config.settings.rp_name,
    )
    return Fido2Server(rp)


def begin_registration(
    serial: str,
    existing_credentials: list[AttestedCredentialData] | None = None,
) -> RegistrationChallenge:
    """Start a FIDO2 registration ceremony.

    Returns challenge options to send to the authenticator and server state
    to keep for complete_registration.
    """
    server = _get_server()
    user = PublicKeyCredentialUserEntity(
        id=serial.encode(),
        name=serial,
        display_name=f"YubiKey {serial}",
    )
    creation_options, state = server.register_begin(
        user=user,
        credentials=existing_credentials or [],
    )
    logger.info("Registration ceremony started for serial=%s", serial)
    return RegistrationChallenge(
        options=dict(creation_options),
        state=state,
    )


def complete_registration(
    state: dict,
    response: dict,
) -> AttestedCredentialData:
    """Finish a FIDO2 registration ceremony.

    Returns the AttestedCredentialData containing the public key and credential ID.
    """
    server = _get_server()
    auth_data = server.register_complete(state, response)
    credential = auth_data.credential_data
    if credential is None:
        raise ValueError("Registration response did not contain credential data")
    logger.info("Registration completed, credential_id=%s", credential.credential_id.hex())
    return credential


def begin_authentication(
    credentials: list[AttestedCredentialData],
) -> AuthenticationChallenge:
    """Start a FIDO2 authentication ceremony.

    credentials: list of previously registered AttestedCredentialData.
    """
    server = _get_server()
    request_options, state = server.authenticate_begin(credentials=credentials)
    logger.info("Authentication ceremony started")
    return AuthenticationChallenge(
        options=dict(request_options),
        state=state,
    )


def complete_authentication(
    state: dict,
    credentials: list[AttestedCredentialData],
    response: dict,
) -> AttestedCredentialData:
    """Finish a FIDO2 authentication ceremony.

    Returns the matching AttestedCredentialData for the authenticated key.
    """
    server = _get_server()
    credential = server.authenticate_complete(state, credentials, response)
    logger.info("Authentication completed")
    return credential
