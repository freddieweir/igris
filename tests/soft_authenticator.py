"""Software FIDO2 authenticator for testing.

Produces valid WebAuthn registration and authentication responses
using real cryptographic operations (ES256 / P-256).

The response dicts match the structure expected by fido2 v2.x
RegistrationResponse.from_dict() and AuthenticationResponse.from_dict().
"""

import hashlib
import os
import struct

from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes

from fido2 import cbor
from fido2.cose import ES256
from fido2.webauthn import (
    Aaguid,
    AttestedCredentialData,
)


class SoftAuthenticator:
    """A software-based FIDO2 authenticator for testing."""

    def __init__(self):
        self._private_key = ec.generate_private_key(ec.SECP256R1())
        self._credential_id = os.urandom(32)
        self._sign_count = 0
        self._aaguid = Aaguid(os.urandom(16))

    @property
    def credential_id(self) -> bytes:
        return self._credential_id

    def make_credential(self, rp_id: str, challenge: str, origin: str) -> dict:
        """Create a registration response matching fido2 v2.x RegistrationResponse format.

        Args:
            rp_id: The relying party ID.
            challenge: The base64url-encoded challenge string from the server.
            origin: The origin URL (e.g., "https://igris.local:8920").
        """
        public_key = self._private_key.public_key()
        public_numbers = public_key.public_numbers()

        # Build COSE key (ES256)
        cose_key = {
            1: 2,    # kty: EC2
            3: -7,   # alg: ES256
            -1: 1,   # crv: P-256
            -2: public_numbers.x.to_bytes(32, "big"),
            -3: public_numbers.y.to_bytes(32, "big"),
        }

        # Build attested credential data
        aaguid_bytes = bytes(self._aaguid)
        cred_id_len = struct.pack(">H", len(self._credential_id))
        cose_key_bytes = cbor.encode(cose_key)
        attested_cred_data = aaguid_bytes + cred_id_len + self._credential_id + cose_key_bytes

        # Build authenticator data
        rp_id_hash = hashlib.sha256(rp_id.encode()).digest()
        flags = 0x41  # UP + AT
        sign_count = struct.pack(">I", self._sign_count)
        auth_data_bytes = rp_id_hash + struct.pack("B", flags) + sign_count + attested_cred_data

        # Build clientDataJSON
                # challenge is already base64url-encoded from the fido2 server
        client_data_json = (
            f'{{"type":"webauthn.create","challenge":"{challenge}",'
            f'"origin":"{origin}"}}'
        ).encode()

        client_data_hash = hashlib.sha256(client_data_json).digest()

        # Self-attestation: sign auth_data || client_data_hash
        sig_input = auth_data_bytes + client_data_hash
        signature = self._private_key.sign(sig_input, ec.ECDSA(hashes.SHA256()))

        att_obj = cbor.encode({
            "fmt": "packed",
            "attStmt": {
                "alg": -7,
                "sig": signature,
            },
            "authData": auth_data_bytes,
        })

        # Match fido2 v2.x RegistrationResponse.from_dict() format
        return {
            "rawId": self._credential_id,
            "response": {
                "clientDataJSON": client_data_json,
                "attestationObject": att_obj,
            },
            "type": "public-key",
        }

    def get_assertion(self, rp_id: str, challenge: str, origin: str) -> dict:
        """Create an authentication response matching fido2 v2.x AuthenticationResponse format.

        Args:
            rp_id: The relying party ID.
            challenge: The base64url-encoded challenge string from the server.
            origin: The origin URL.
        """
        self._sign_count += 1

        rp_id_hash = hashlib.sha256(rp_id.encode()).digest()
        flags = 0x01  # UP
        sign_count = struct.pack(">I", self._sign_count)
        auth_data_bytes = rp_id_hash + struct.pack("B", flags) + sign_count

        # Build clientDataJSON
        # challenge is already base64url-encoded from the fido2 server
        client_data_json = (
            f'{{"type":"webauthn.get","challenge":"{challenge}",'
            f'"origin":"{origin}"}}'
        ).encode()

        client_data_hash = hashlib.sha256(client_data_json).digest()

        sig_input = auth_data_bytes + client_data_hash
        signature = self._private_key.sign(sig_input, ec.ECDSA(hashes.SHA256()))

        return {
            "rawId": self._credential_id,
            "response": {
                "clientDataJSON": client_data_json,
                "authenticatorData": auth_data_bytes,
                "signature": signature,
            },
            "type": "public-key",
        }

    def get_attested_credential_data(self) -> AttestedCredentialData:
        """Build an AttestedCredentialData from this authenticator's key."""
        public_key = self._private_key.public_key()
        cose_key = ES256.from_cryptography_key(public_key)
        return AttestedCredentialData.create(
            self._aaguid,
            self._credential_id,
            cose_key,
        )
