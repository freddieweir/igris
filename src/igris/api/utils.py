"""Shared API utilities."""

import base64


def serialize_fido2_options(options: dict) -> dict:
    """Convert fido2 options to JSON-safe dict.

    Recursively converts bytes to base64url strings and dataclass-like
    objects to dicts. Used by both auth and key registration endpoints.

    Note: Challenge state is stored in-memory (module-level dicts in
    auth.py and keys.py). This requires a single-worker deployment.
    Multi-worker setups would need Redis or database-backed state.
    """

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
