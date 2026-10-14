"""test_hardening.py — T2: rate limits, size caps, replay, schemas, generic errors."""
import asyncio
import logging
import json

import pytest

pytest.importorskip("fastapi")
pytest.importorskip("httpx")

from fastapi.testclient import TestClient  # noqa: E402

import api  # noqa: E402
import hardening  # noqa: E402
import security  # noqa: E402

TOKEN_A = "a" * 32
TOKEN_B = "b" * 32
GOOD_FINDING = {"code": "DEV_OPTIONS_ENABLED", "facets": {}}


class Stub:
    def __init__(self):
        self.prompts = []

    def get_llm_response(self, p):
        self.prompts.append(p)
        return "stub"

    def respond(self, q, use_rag=True):
        self.prompts.append(q)
        return "stub"


@pytest.fixture
def env(monkeypatch):
    stub = Stub()
    monkeypatch.setattr(api, "assistant_instance", stub)
    monkeypatch.setattr(api, "_llm_semaphore", asyncio.Semaphore(4))
    monkeypatch.setattr(hardening, "security_limiter", security.RateLimiter(3, 60))
    monkeypatch.setattr(security, "rate_limiter", security.RateLimiter(2, 60))
    monkeypatch.setattr(hardening, "replay_guard", hardening.ReplayGuard())
    api.cache_manager.clear()
    return TestClient(api.app, raise_server_exceptions=False), stub


def post_findings(c, token=TOKEN_A, **extra):
    return c.post("/api/security/findings",
                  json={"findings": [GOOD_FINDING], "want_ai": False, **extra},
                  headers={"X-Install-Token": token})


# ── rate limiting ────────────────────────────────────────────────────────────
def test_security_routes_are_rate_limited(env):
    c, _ = env
    assert [post_findings(c).status_code for _ in range(3)] == [200, 200, 200]
    r = post_findings(c)
    assert r.status_code == 429 and r.headers["retry-after"] == "60"


def test_every_security_route_is_covered(env):
    c, _ = env
    for _ in range(3):
        c.get("/api/security/findings/registry", headers={"X-Install-Token": TOKEN_A})
    assert c.get("/api/security/findings/registry",
                 headers={"X-Install-Token": TOKEN_A}).status_code == 429
    assert c.post("/api/security/apps", headers={"X-Install-Token": TOKEN_A}).status_code == 429


def test_limits_are_per_install_token_not_shared(env):
    c, _ = env
    for _ in range(3):
        post_findings(c, TOKEN_A)
    assert post_findings(c, TOKEN_A).status_code == 429
    assert post_findings(c, TOKEN_B).status_code == 200


def test_chat_is_rate_limited_and_user_id_cannot_dodge_it(env):
    c, _ = env
    codes = []
    for i in range(3):
        r = c.post("/api/chat", json={"query": f"what is phishing {i}", "user_id": f"spoof{i}"},
                   headers={"X-Install-Token": TOKEN_A})
        codes.append(r.status_code)
    assert codes == [200, 200, 429]


def test_malformed_token_falls_back_to_hashed_peer(env):
    assert hardening.client_key("not-a-token!", "1.2.3.4").startswith("ip:")
    assert "1.2.3.4" not in hardening.client_key(None, "1.2.3.4")
    assert hardening.client_key(TOKEN_A, "1.2.3.4").startswith("t:")
    assert TOKEN_A not in hardening.client_key(TOKEN_A, "1.2.3.4")


def test_no_ip_in_logs(env, caplog):
    c, _ = env
    with caplog.at_level(logging.DEBUG):
        for _ in range(5):
            c.get("/api/security/findings/registry")   # no token -> peer fallback
    text = " ".join(r.getMessage() for r in caplog.records)
    assert "testclient" not in text and "127.0.0.1" not in text


def test_access_log_filter_blanks_peer():
    rec = logging.LogRecord("uvicorn.access", logging.INFO, "", 0,
                            '%s - "%s %s HTTP/%s" %d',
                            ("203.0.113.9:5000", "POST", "/x", "1.1", 200), None)
    hardening.RedactPeerAddress().filter(rec)
    assert "203.0.113.9" not in rec.getMessage()


# ── size cap ─────────────────────────────────────────────────────────────────
def test_oversized_body_rejected(env):
    c, _ = env
    big = json.dumps({"findings": [GOOD_FINDING], "pad": "x" * (hardening.MAX_BODY_BYTES + 10)})
    r = c.post("/api/security/findings", content=big, headers={"Content-Type": "application/json"})
    assert r.status_code == 413


def test_oversized_chunked_body_rejected(env):
    c, _ = env

    def gen():
        for _ in range(hardening.MAX_BODY_BYTES // 1024 + 5):
            yield b"x" * 1024

    r = c.post("/api/security/findings", content=gen(),
               headers={"Content-Type": "application/json"})
    assert r.status_code == 413


# ── replay ───────────────────────────────────────────────────────────────────
def test_replayed_nonce_is_rejected(env):
    c, _ = env
    h = {"X-Install-Token": TOKEN_A, "X-Request-Nonce": "nonce-12345678"}
    body = {"findings": [GOOD_FINDING], "want_ai": False}
    assert c.post("/api/security/findings", json=body, headers=h).status_code == 200
    assert c.post("/api/security/findings", json=body, headers=h).status_code == 409


def test_replay_guard_expires_and_is_bounded():
    g = hardening.ReplayGuard(window_s=10, max_entries=3)
    assert g.first_use("k", "n1", now=0)
    assert not g.first_use("k", "n1", now=5)
    assert g.first_use("k", "n1", now=20)          # expired
    for i in range(10):
        g.first_use("k", f"x{i}", now=21)
    assert len(g._seen) <= 3


def test_bad_nonce_rejected(env):
    c, _ = env
    r = post_findings(c)
    r = c.post("/api/security/findings", json={"findings": [GOOD_FINDING]},
               headers={"X-Request-Nonce": "bad nonce!!"})
    assert r.status_code == 400


# ── schemas ──────────────────────────────────────────────────────────────────
def test_schema_version_defaults_and_is_checked(env):
    c, _ = env
    assert post_findings(c).status_code == 200                       # absent -> current
    assert post_findings(c, TOKEN_B, schema_version=1).status_code == 200
    assert post_findings(c, "c" * 32, schema_version=99).status_code == 400


def test_unknown_fields_rejected_without_echo(env):
    c, _ = env
    secret = "com.mybank.private.9876"
    r = c.post("/api/security/findings",
               json={"findings": [GOOD_FINDING], "packages": [secret]},
               headers={"X-Install-Token": TOKEN_A})
    assert r.status_code == 422
    assert secret not in r.text and r.json() == {"detail": "Invalid request."}


def test_chat_extra_field_rejected_and_length_capped(env):
    c, _ = env
    assert c.post("/api/chat", json={"query": "hello there", "extra": 1}).status_code == 422
    assert c.post("/api/chat", json={"query": "a" * 5000}).status_code == 422


# ── generic errors ───────────────────────────────────────────────────────────
def test_unhandled_error_is_generic(env, monkeypatch):
    c, stub = env

    def boom(*a, **k):
        raise RuntimeError("secret internal path /srv/app/key.pem")

    monkeypatch.setattr(stub, "respond", boom)
    r = c.post("/api/chat", json={"query": "hello there"})
    assert r.status_code == 500
    assert "key.pem" not in r.text and "RuntimeError" not in r.text


def test_health_hides_init_traceback(env, monkeypatch):
    c, _ = env
    monkeypatch.setitem(api._init_status, "error", "Traceback ... /srv/secret.py")
    body = c.get("/api/health").json()
    assert "secret.py" not in json.dumps(body)


# ── CORS ─────────────────────────────────────────────────────────────────────
def test_cors_only_for_listed_origins(env):
    c, _ = env
    ok = c.get("/api/health", headers={"Origin": api.ALLOWED_ORIGINS[0]})
    bad = c.get("/api/health", headers={"Origin": "https://evil.example"})
    assert ok.headers.get("access-control-allow-origin") == api.ALLOWED_ORIGINS[0]
    assert "access-control-allow-origin" not in bad.headers
