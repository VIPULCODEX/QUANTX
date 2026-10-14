"""
hardening.py — request-level controls for the QuantX API.

Pure ASGI middleware, so it runs before routing and body parsing:

  * body size cap (Content-Length, and a bounded read when it is absent)
  * per-install rate limiting on /api/chat and every /api/security/* route
  * replay control for requests that carry a nonce

Identity: the client sends a random per-install token. It is generated on the
phone from a CSPRNG and is not derived from any device identifier. When it is
missing or malformed the limiter falls back to the peer address — but only a
truncated hash of either is ever held in memory or written to a log, never the
raw IP address.
"""

import hashlib
import json
import re
import time
from collections import OrderedDict
from typing import Optional

import signing
from security import RateLimiter

INSTALL_TOKEN_HEADER = b"x-install-token"
NONCE_HEADER = b"x-request-nonce"

MAX_BODY_BYTES = 64 * 1024
REPLAY_WINDOW_S = 300
REPLAY_MAX_ENTRIES = 10_000

_TOKEN_RE = re.compile(r"^[0-9a-f]{32,64}$")
_NONCE_RE = re.compile(r"^[0-9a-zA-Z_-]{8,64}$")

# /api/chat keeps the existing limiter in security.py; the findings family gets
# its own bucket so scanning cannot starve chat and vice versa.
security_limiter = RateLimiter(max_requests=30, window_seconds=60)


def _h(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8", "ignore")).hexdigest()[:16]


def client_key(token: Optional[str], peer_ip: Optional[str]) -> str:
    if token and _TOKEN_RE.match(token):
        return "t:" + _h(token)
    return "ip:" + _h(peer_ip or "unknown")


class ReplayGuard:
    """Remembers (client, nonce) pairs for a short window; bounded in size."""

    def __init__(self, window_s: int = REPLAY_WINDOW_S, max_entries: int = REPLAY_MAX_ENTRIES):
        self._seen: "OrderedDict[str, float]" = OrderedDict()
        self._window = window_s
        self._max = max_entries

    def first_use(self, key: str, nonce: str, now: Optional[float] = None) -> bool:
        now = time.time() if now is None else now
        while self._seen:
            oldest_key, ts = next(iter(self._seen.items()))
            if now - ts > self._window or len(self._seen) >= self._max:
                self._seen.popitem(last=False)
            else:
                break
        k = f"{key}|{nonce}"
        if k in self._seen:
            return False
        self._seen[k] = now
        return True


replay_guard = ReplayGuard()


def is_guarded(path: str) -> bool:
    return path == "/api/chat" or path.startswith("/api/security/")


def _limiter_for(path: str) -> RateLimiter:
    # Imported lazily so tests can swap api.rate_limiter.
    from security import rate_limiter
    return rate_limiter if path == "/api/chat" else security_limiter


async def _send_json(send, status: int, body: dict, extra_headers=()):
    payload = json.dumps(body).encode()
    headers = [(b"content-type", b"application/json"),
               (b"content-length", str(len(payload)).encode()), *extra_headers]
    await send({"type": "http.response.start", "status": status, "headers": headers})
    await send({"type": "http.response.body", "body": payload})


class HardeningMiddleware:
    def __init__(self, app, max_body: int = MAX_BODY_BYTES):
        self.app = app
        self.max_body = max_body

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or not is_guarded(scope["path"]):
            return await self.app(scope, receive, send)

        headers = {k.lower(): v for k, v in scope["headers"]}
        peer = (scope.get("client") or (None,))[0]
        token = headers.get(INSTALL_TOKEN_HEADER, b"").decode("latin-1")
        key = client_key(token, peer)
        path = scope["path"]

        # 1. Rate limit (before reading any body).
        if not _limiter_for(path).is_allowed(key):
            return await _send_json(send, 429, {"detail": "Rate limit exceeded. Wait and retry."},
                                    [(b"retry-after", b"60")])

        # 2. Body size. A body is only buffered when it has no Content-Length
        #    (chunked) or when signature checking needs the raw bytes.
        declared = headers.get(b"content-length")
        needs_body = (signing.mode() != "off" and path == signing.SIGNED_PATH
                      and scope["method"] == "POST")
        if declared is not None:
            try:
                too_big = int(declared) > self.max_body
            except ValueError:
                too_big = True
            if too_big:
                return await _send_json(send, 413, {"detail": "Request too large."})
        body_receive = receive
        if declared is None or needs_body:
            chunks, size = [], 0
            while True:
                msg = await receive()
                if msg["type"] != "http.request":
                    break
                size += len(msg.get("body", b""))
                if size > self.max_body:
                    return await _send_json(send, 413, {"detail": "Request too large."})
                chunks.append(msg)
                if not msg.get("more_body"):
                    break
            it = iter(chunks)

            async def body_receive():
                try:
                    return next(it)
                except StopIteration:
                    return await receive()

            if needs_body:
                raw = b"".join(m.get("body", b"") for m in chunks)
                reason = signing.check(
                    key, headers.get(b"x-request-nonce", b"").decode("latin-1"), raw,
                    headers.get(signing.SIG_HEADER, b"").decode("latin-1"),
                    headers.get(signing.KEY_HEADER, b"").decode("latin-1"))
                if reason:
                    return await _send_json(send, 401, {"detail": "Invalid signature."})

        # 3. Replay control (optional header; present-but-reused is rejected).
        nonce = headers.get(NONCE_HEADER, b"").decode("latin-1")
        if nonce:
            if not _NONCE_RE.match(nonce):
                return await _send_json(send, 400, {"detail": "Invalid request."})
            if not replay_guard.first_use(key, nonce):
                return await _send_json(send, 409, {"detail": "Duplicate request."})

        return await self.app(scope, body_receive, send)


class RedactPeerAddress:
    """logging.Filter: blank the client address in uvicorn/gunicorn access logs."""

    def filter(self, record) -> bool:
        if isinstance(record.args, tuple) and record.args:
            record.args = ("-",) + record.args[1:]
        return True
