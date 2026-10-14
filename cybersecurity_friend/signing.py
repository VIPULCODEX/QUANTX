"""
signing.py — optional request signing for /api/security/findings.

What it is: a trust-on-first-use (TOFU) HMAC. On its first request an install
sends the signing key it derived (X-Install-Key); the server remembers it for
that install token. Every later request carries
    X-Signature = HMAC-SHA256(key, nonce + "\\n" + raw_body)
and the server recomputes it. The payload itself (toWire output) is unchanged.

What it buys: a party that does not hold the install's key - an off-path
attacker, a script replaying captured bodies with new nonces, a proxy that edits
a body - cannot produce a valid request for that install once it has registered.

What it does NOT do: it does not authenticate the *device* (the key is generated
by the app, not provisioned or attested), it does not stop a compromised phone
from signing forged findings, it does not stop whoever registers a token first,
and keys live in server memory, so a restart re-opens registration. See
docs/payload_signing.md. Android Key Attestation remains future work.

SIGNING_MODE (env): off (default) | verify (check when present, reject bad ones,
accept unsigned) | enforce (require a valid signature on the findings route).
"""
import hashlib
import hmac
import os
import re
from collections import OrderedDict
from typing import Optional

KEY_HEADER = b"x-install-key"
SIG_HEADER = b"x-signature"
SIGNED_PATH = "/api/security/findings"

_HEX64 = re.compile(r"^[0-9a-f]{64}$")
MAX_KEYS = 50_000


def mode() -> str:
    m = os.getenv("SIGNING_MODE", "off").strip().lower()
    return m if m in {"off", "verify", "enforce"} else "off"


def sign(key_hex: str, nonce: str, body: bytes) -> str:
    return hmac.new(bytes.fromhex(key_hex), nonce.encode() + b"\n" + body, hashlib.sha256).hexdigest()


class KeyStore:
    def __init__(self, max_keys: int = MAX_KEYS):
        self._keys: "OrderedDict[str, str]" = OrderedDict()
        self._max = max_keys

    def get(self, client: str) -> Optional[str]:
        k = self._keys.get(client)
        if k is not None:
            self._keys.move_to_end(client)
        return k

    def register_if_new(self, client: str, key_hex: str) -> bool:
        if not _HEX64.match(key_hex or "") or client in self._keys:
            return False
        self._keys[client] = key_hex
        while len(self._keys) > self._max:
            self._keys.popitem(last=False)
        return True


key_store = KeyStore()


def check(client: str, nonce: str, body: bytes, signature: str, offered_key: str) -> Optional[str]:
    """Return None if the request is acceptable, else a short reason code.
    `client` must be a token-derived key ('t:...'); IP-fallback clients are
    treated as unsigned."""
    m = mode()
    if m == "off":
        return None
    have_token = client.startswith("t:")
    if have_token and offered_key:
        key_store.register_if_new(client, offered_key)
    key = key_store.get(client) if have_token else None
    if not signature:
        return "missing" if m == "enforce" else None
    if key is None or not nonce:
        return "unregistered"
    if not _HEX64.match(signature):
        return "malformed"
    if not hmac.compare_digest(sign(key, nonce, body), signature):
        return "mismatch"
    return None
