"""test_signing.py — T10: optional TOFU HMAC over the request body."""
import asyncio
import json

import pytest

pytest.importorskip("fastapi")
from fastapi.testclient import TestClient  # noqa: E402

import api  # noqa: E402
import hardening  # noqa: E402
import security  # noqa: E402
import signing  # noqa: E402

TOKEN = "c" * 32
KEY = "ab" * 32
BODY = {"findings": [{"code": "DEV_OPTIONS_ENABLED", "facets": {}}], "want_ai": False}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(api, "assistant_instance", None)
    monkeypatch.setattr(hardening, "security_limiter", security.RateLimiter(100, 60))
    monkeypatch.setattr(hardening, "replay_guard", hardening.ReplayGuard())
    monkeypatch.setattr(signing, "key_store", signing.KeyStore())
    return TestClient(api.app, raise_server_exceptions=False)


def post(c, body=BODY, nonce="nonce-0001abc", key=KEY, offer=False, sig=None, token=TOKEN, raw=None):
    data = raw if raw is not None else json.dumps(body, separators=(",", ":")).encode()
    h = {"X-Install-Token": token, "X-Request-Nonce": nonce, "Content-Type": "application/json"}
    h["X-Signature"] = sig if sig is not None else signing.sign(key, nonce, data)
    if offer:
        h["X-Install-Key"] = key
    return c.post("/api/security/findings", content=data, headers=h)


def test_sign_known_vector():
    # RFC 4231 test case 2, adapted: message = nonce + "\n" + body
    import hashlib, hmac
    key = bytes.fromhex(KEY)
    assert signing.sign(KEY, "n", b"b") == hmac.new(key, b"n\nb", hashlib.sha256).hexdigest()


def test_mode_off_ignores_signatures(client, monkeypatch):
    monkeypatch.delenv("SIGNING_MODE", raising=False)
    assert post(client, sig="00" * 32).status_code == 200


def test_verify_mode_registers_then_checks(client, monkeypatch):
    monkeypatch.setenv("SIGNING_MODE", "verify")
    assert post(client, offer=True, nonce="nonce-0001abc").status_code == 200       # register + verify
    assert post(client, nonce="nonce-0002abc").status_code == 200                   # verified
    assert post(client, nonce="nonce-0003abc", sig="00" * 32).status_code == 401    # wrong signature


def test_tampered_body_rejected(client, monkeypatch):
    monkeypatch.setenv("SIGNING_MODE", "verify")
    post(client, offer=True, nonce="nonce-0001abc")
    good = json.dumps(BODY, separators=(",", ":")).encode()
    sig = signing.sign(KEY, "nonce-0002abc", good)
    tampered = json.dumps({**BODY, "want_ai": True}, separators=(",", ":")).encode()
    r = post(client, nonce="nonce-0002abc", sig=sig, raw=tampered)
    assert r.status_code == 401


def test_other_party_cannot_sign_for_a_registered_install(client, monkeypatch):
    monkeypatch.setenv("SIGNING_MODE", "verify")
    post(client, offer=True, nonce="nonce-0001abc")
    attacker_key = "cd" * 32
    assert post(client, nonce="nonce-0004abc", key=attacker_key, offer=True).status_code == 401


def test_first_key_wins_and_later_offers_are_ignored(client, monkeypatch):
    monkeypatch.setenv("SIGNING_MODE", "verify")
    post(client, offer=True, nonce="nonce-0001abc")
    assert signing.key_store.get(hardening.client_key(TOKEN, None)) == KEY


def test_enforce_requires_signature(client, monkeypatch):
    monkeypatch.setenv("SIGNING_MODE", "enforce")
    unsigned = client.post("/api/security/findings", json=BODY, headers={"X-Install-Token": TOKEN})
    assert unsigned.status_code == 401
    assert post(client, offer=True, nonce="nonce-0001abc").status_code == 200


def test_replayed_nonce_still_rejected_with_valid_signature(client, monkeypatch):
    monkeypatch.setenv("SIGNING_MODE", "enforce")
    assert post(client, offer=True, nonce="nonce-0001abc").status_code == 200
    assert post(client, nonce="nonce-0001abc").status_code == 409


def test_other_routes_unaffected(client, monkeypatch):
    monkeypatch.setenv("SIGNING_MODE", "enforce")
    assert client.get("/api/security/findings/registry").status_code == 200


def test_invalid_key_format_not_registered():
    ks = signing.KeyStore()
    assert not ks.register_if_new("t:x", "short")
    assert ks.register_if_new("t:x", KEY) and not ks.register_if_new("t:x", "ef" * 32)


def test_shared_vector():
    """Pinned in cyber_intel_app/test/signer_test.dart so both ends agree."""
    body = b'{"want_ai":true,"findings":[{"code":"DEV_OPTIONS_ENABLED","facets":{}}]}'
    assert signing.sign("ab" * 32, "nonce-0001abc", body) == \
        "31636f035765cddde3bc0b5cb49fa3465eb1c803117bd25bbc2443fb25fb17c8"
