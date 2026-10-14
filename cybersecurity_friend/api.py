"""
api.py — QuantX Production FastAPI Backend  v3.0.0
====================================================

v3 Scalability Upgrades:
  1. ASYNC endpoint — `async def handle_chat` runs in the event loop, not
     a threadpool, so thousands of I/O-waiting coroutines are cheap.
  2. Groq Semaphore — hard cap on concurrent LLM calls so we never spam
     the Groq API (free tier ~30 req/min). Excess requests queue and wait
     rather than crashing.
  3. Request Queue Timeout — if a request waits > QUEUE_TIMEOUT_S in the
     semaphore queue it gets a 503 (retry-after) instead of hanging forever.
  4. Stampede-safe cache — cache_manager.get_or_compute() ensures only ONE
     coroutine calls the LLM for a cold query; all others await the result.
  5. gunicorn-ready — start with `gunicorn -k uvicorn.workers.UvicornWorker`
     for multiple OS-level processes (Render / production).
  6. /api/metrics endpoint — live visibility: queue depth, cache stats,
     semaphore slots remaining.
"""

import asyncio
import re
import time
import logging
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from rag_pipeline import RAGPipeline
from assistant import CybersecurityAssistant
from config import TOP_K, GROQ_API_KEY, GROQ_API_KEY_LIST, LLM_MAX_TOKENS
from security import validate_query
from cache_manager import cache_manager
from hardening import HardeningMiddleware, RedactPeerAddress
import untrusted
import leakage

# ─────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("quantx.api")
logger.setLevel(logging.INFO)

# Access logs carry the peer IP by default; blank it. (User-Agent is not in the
# default format and the app never logs it.)
for _n in ("uvicorn.access", "gunicorn.access"):
    logging.getLogger(_n).addFilter(RedactPeerAddress())

# Browser origins allowed to call this API. Native app requests send no Origin
# header and are unaffected. Edit this list, or set QUANTX_CORS_ORIGINS to a
# comma-separated override.
import os as _os_cors
ALLOWED_ORIGINS = [
    o.strip() for o in _os_cors.getenv(
        "QUANTX_CORS_ORIGINS",
        "https://vipulcdex-quantx.hf.space,http://localhost:3000,http://localhost:8501",
    ).split(",") if o.strip()
]

# Version of the findings request schema this server speaks.
FINDINGS_SCHEMA_VERSION = 1

# ─────────────────────────────────────────────────────────────────────────────
# Concurrency Controls (Scaled dynamically based on multi-key pool size)
# ─────────────────────────────────────────────────────────────────────────────
# Groq free tier ≈ 30 req/min => We assign 10 concurrent slots per API key.
# If you provide 4 keys, local queue handles up to 40 seamless concurrent requests.
MAX_CONCURRENT_LLM_CALLS = int(10 * max(1, len(GROQ_API_KEY_LIST)))

# Max seconds a request will wait in the semaphore queue before giving up.
QUEUE_TIMEOUT_S = 30.0

# Populated at startup
_llm_semaphore: Optional[asyncio.Semaphore] = None

# Populated by the background init thread. Must exist at module scope from the
# start — otherwise any request arriving before _background_init's first
# assignment hits a NameError instead of the intended "still initializing" path.
assistant_instance: Optional[CybersecurityAssistant] = None
rag_instance: Optional[RAGPipeline] = None

# Tracks whether background init is done
_init_status = {"ready": False, "error": None, "progress": "Not started"}

# Metrics counters (per-process; reset on restart)
_metrics = {
    "total_requests": 0,
    "cache_hits": 0,
    "llm_calls": 0,
    "rate_limited": 0,
    "errors": 0,
    "queue_timeouts": 0,
}


# ─────────────────────────────────────────────────────────────────────────────
# Background initializer — runs in a thread so server starts INSTANTLY
# ─────────────────────────────────────────────────────────────────────────────
def _background_init():
    """Load RAG pipeline + assistant in a worker thread.
    The server is already accepting requests while this runs.
    Health check returns 'initializing' until this completes.
    """
    global assistant_instance, rag_instance
    try:
        _init_status["progress"] = "Loading embedding model..."
        logger.info("[BG] Starting background RAG initialization...")

        rag = RAGPipeline()
        _init_status["progress"] = "Initializing FAISS indices..."
        rag.initialize()

        _init_status["progress"] = "Building assistant..."
        retriever = rag.get_retriever(k=TOP_K)
        assistant = CybersecurityAssistant(retriever, max_tokens=LLM_MAX_TOKENS)

        # Assign atomically so no half-initialized state is visible
        rag_instance = rag
        assistant_instance = assistant

        _init_status["ready"] = True
        _init_status["progress"] = "Ready"
        logger.info("[BG] QuantX Neural Core ready!")
    except Exception:
        import traceback
        err = traceback.format_exc()
        _init_status["error"] = err
        _init_status["progress"] = "Failed"
        logger.error("[BG] Init failed:\n%s", err)


# ─────────────────────────────────────────────────────────────────────────────
# Lifespan (startup / shutdown)
# ─────────────────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    global _llm_semaphore

    # Semaphore must be created inside the running event loop
    _llm_semaphore = asyncio.Semaphore(MAX_CONCURRENT_LLM_CALLS)

    if not GROQ_API_KEY:
        logger.error("GROQ_API_KEY is not set — chat will fail.")

    # ── Launch RAG init in a background thread so server starts INSTANTLY ──
    # HF Spaces health check hits /api/health immediately after gunicorn starts.
    # Without this, the blocking model load causes the health check to time out.
    import threading
    _init_status["progress"] = "Starting background loader..."
    t = threading.Thread(target=_background_init, daemon=True, name="QuantX-Init")
    t.start()
    logger.info("Server UP immediately. RAG pipeline loading in background thread...")

    yield  # ← server is fully alive and accepting requests here

    cache_manager.clear()
    logger.info("Shutdown complete.")


# ─────────────────────────────────────────────────────────────────────────────
# FastAPI App
# ─────────────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="QuantX AI Production API",
    description="Secure, Async, Rate-limited, Cached RAG Backend for Cybersecurity",
    version="3.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "X-Install-Token", "X-Request-Nonce"],
)
app.add_middleware(HardeningMiddleware)


@app.exception_handler(RequestValidationError)
async def _invalid_request(request: Request, exc: RequestValidationError):
    # The default handler echoes the offending input back; never do that.
    return JSONResponse(status_code=422, content={"detail": "Invalid request."})


@app.exception_handler(Exception)
async def _unexpected_error(request: Request, exc: Exception):
    _metrics["errors"] += 1
    logger.error("Unhandled %s on %s", type(exc).__name__, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal error."})


# ─────────────────────────────────────────────────────────────────────────────
# Models
# ─────────────────────────────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    query: str = Field(max_length=4000)
    user_id: Optional[str] = Field(default=None, max_length=128)  # not used for limiting
    use_rag: Optional[bool] = True


class ChatResponse(BaseModel):
    response: str
    cached: bool
    time_taken: float
    queued: bool = False   # True if request had to wait in the LLM semaphore


# ─────────────────────────────────────────────────────────────────────────────
# POST /api/chat — Main endpoint (ASYNC v3)
# ─────────────────────────────────────────────────────────────────────────────
@app.post("/api/chat", response_model=ChatResponse)
async def handle_chat(request: ChatRequest, client_request: Request):
    """
    Async chat endpoint with:
      - Rate limiting per user/IP
      - Stampede-safe async LRU cache
      - Groq semaphore (queue, don't crash)
      - Queue timeout (503 if waiting too long)
    """
    if assistant_instance is None:
        raise HTTPException(
            status_code=503, 
            detail="Neural Core is initializing or failed to start. Check server logs for import errors or missing config."
        )

    start_time = time.perf_counter()
    _metrics["total_requests"] += 1

    # Rate limiting and body-size control happen in HardeningMiddleware.

    # 2. Input Validation
    try:
        clean_query = validate_query(request.query)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # 3. Cache fast-path (no semaphore needed)
    # We include `use_rag` toggle in the cache key to prevent mismatched caching
    cache_key = f"{clean_query}__rag={request.use_rag}"
    cached_res = await cache_manager.aget(cache_key)
    if cached_res:
        _metrics["cache_hits"] += 1
        logger.info("Cache HIT")
        return ChatResponse(
            response=cached_res,
            cached=True,
            time_taken=round(time.perf_counter() - start_time, 4),
        )

    # 4. LLM call — guard with semaphore + timeout
    queued = False
    try:
        # Try to acquire immediately
        if _llm_semaphore.locked():
            queued = True   # We'll have to wait

        acquired = await asyncio.wait_for(
            _llm_semaphore.acquire(),
            timeout=QUEUE_TIMEOUT_S,
        )
    except asyncio.TimeoutError:
        _metrics["queue_timeouts"] += 1
        raise HTTPException(
            status_code=503,
            detail="Server is under heavy load. Please retry in a few seconds.",
            headers={"Retry-After": "5"},
        )

    try:
        _metrics["llm_calls"] += 1
        # Run the synchronous LLM call in a thread so the event loop stays free
        result = await asyncio.get_event_loop().run_in_executor(
            None,
            lambda: assistant_instance.respond(clean_query, use_rag=request.use_rag)
        )
        await cache_manager.aset(cache_key, result)
        time_taken = time.perf_counter() - start_time
        logger.info("LLM response in %.2fs (queued=%s)", time_taken, queued)
        return ChatResponse(
            response=result,
            cached=False,
            time_taken=round(time_taken, 2),
            queued=queued,
        )
    except Exception as e:
        _metrics["errors"] += 1
        logger.error("LLM error: %s", type(e).__name__)
        raise HTTPException(status_code=500, detail="Could not generate a response.")
    finally:
        _llm_semaphore.release()


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/health  — Always returns 200 so HF Spaces health check passes
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/api/health")
async def health_check():
    # Always HTTP 200 — HF Spaces uses this for health check.
    # pipeline_ready=False means still loading, not broken.
    return {
        "status": "initializing" if not _init_status["ready"] else "online",
        "version": "3.1.0",
        "keys_loaded": bool(GROQ_API_KEY),
        "pipeline_ready": assistant_instance is not None,
        "init_progress": _init_status["progress"],
        "init_error": "initialization failed" if _init_status.get("error") else None,
        "llm_slots_available": _llm_semaphore._value if _llm_semaphore else 0,
        "llm_slots_total": MAX_CONCURRENT_LLM_CALLS,
    }


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/metrics  — Live performance dashboard
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/api/metrics")
async def metrics():
    """Real-time server metrics — no user data exposed."""
    cache_stats = cache_manager.stats()
    return {
        "requests": _metrics,
        "cache": cache_stats,
        "concurrency": {
            "max_llm_slots": MAX_CONCURRENT_LLM_CALLS,
            "available_slots": _llm_semaphore._value if _llm_semaphore else 0,
            "queue_timeout_s": QUEUE_TIMEOUT_S,
        },
    }


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/cache/stats
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/api/cache/stats")
async def cache_stats():
    return cache_manager.stats()


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/rag/status
# ─────────────────────────────────────────────────────────────────────────────
@app.get("/api/rag/status")
async def rag_status():
    if rag_instance is None:
        return {"pipeline_ready": False, "message": "RAG not initialized"}
    return rag_instance.get_index_status()


# ─────────────────────────────────────────────────────────────────────────────
# SECURITY SCANNER ENDPOINTS (PhishSense + Android Telemetry)
# ─────────────────────────────────────────────────────────────────────────────
import pickle, os as _os

_phish_model = None

def _get_phish_model():
    global _phish_model
    if _phish_model is None:
        model_path = _os.path.join(_os.path.dirname(__file__), "model", "model.pkl")
        if _os.path.exists(model_path):
            with open(model_path, "rb") as f:
                artifacts = pickle.load(f)
            _phish_model = artifacts["pipeline"]
    return _phish_model


class PhishRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(max_length=10000)


class WifiRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    ssid: str = Field(max_length=64)
    security_type: str = Field(max_length=32)   # e.g. "WPA2", "WPA3", "Open", "WEP"
    is_public: Optional[bool] = False


class DeviceRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    os_version: str = Field(max_length=128)
    usb_debugging: bool
    unknown_sources: bool
    developer_mode: bool
    screen_lock: bool
    google_play_protect: bool


_WIFI_SECURITY_TYPES = {
    "OPEN": "Open", "NONE": "Open", "WEP": "WEP", "WPA": "WPA", "WPA2": "WPA2",
    "WPA3": "WPA3", "WPA2/WPA3": "WPA2/WPA3", "WPA/WPA2": "WPA/WPA2",
}


@app.post("/api/security/phishing")
async def analyze_phishing(req: PhishRequest):
    """
    Run PhishSense ML + rule engine on arbitrary text/URL.
    Returns raw ML output + an LLM-generated plain-English explanation.
    """
    try:
        from inference import analyze_text
        result = analyze_text(req.text, model=_get_phish_model())
    except Exception as e:
        logger.error("PhishSense error: %s", type(e).__name__)
        raise HTTPException(status_code=500, detail="Analysis failed.")

    # Build LLM explanation if assistant is ready
    explanation = ""
    if assistant_instance:
        prompt = (
            f"A user submitted the following text for phishing analysis:\n\n"
            f"\"{untrusted.wrap_if_enabled(req.text, 'sample', 4000)}\"\n\n"
            f"The PhishSense ML model returned:\n"
            f"- Prediction: {result['prediction']}\n"
            f"- Risk Score: {result['risk_score']}%\n"
            f"- Reasons: {', '.join(result['reasons'])}\n"
            f"- URL Flag: {result['url_flag']}\n\n"
            f"In 3-4 sentences, explain to the user in plain English what this means, "
            f"whether they are at risk, and what they should do next."
        )
        try:
            explanation = await asyncio.get_event_loop().run_in_executor(
                None, lambda: assistant_instance.get_llm_response(prompt)
            )
        except Exception:
            explanation = "Could not generate AI explanation at this time."

    return {**result, "ai_explanation": untrusted.guard_answer(explanation)}


# Every reason string the on-device or server PhishSense can produce. The explain
# route accepts only these, so no client text can reach the prompt through it.
PHISH_REASONS = frozenset({
    "Urgency detected",
    "Account verification pressure detected",
    "OTP solicitation detected",
    "Job/earning lure detected",
    "Financial lure detected",
    "Obfuscated wording detected",
    "No major scam indicators found",
    "Suspicious URL found",
    "URL present but no high-risk domain pattern found",
    "Shortened link detected",
    "Suspicious domain extension found",
    "Random-looking domain detected",
})
PHISH_CLASSES = ("phishing", "otp_scam", "job_scam", "lottery", "safe")


class PhishExplainRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    prediction: str = Field(max_length=16)
    risk_score: int = Field(ge=0, le=100)
    reasons: list = Field(default_factory=list, max_length=16)
    url_flag: str = Field(default="Safe", max_length=16)


@app.post("/api/security/phishing/explain")
async def explain_phishing_verdict(req: PhishExplainRequest):
    """Explain a verdict that was computed ON THE DEVICE.

    Receives only the class, score, signal names and URL flag - never the message
    or any link - and builds the prompt from closed sets, so the assistant (and
    the model provider) learn nothing about what the user was checking.
    """
    if req.prediction not in PHISH_CLASSES:
        raise HTTPException(status_code=422, detail="Invalid request.")
    reasons = [r for r in req.reasons if isinstance(r, str) and r in PHISH_REASONS]
    url_flag = "Suspicious" if req.url_flag == "Suspicious" else "Safe"
    if assistant_instance is None:
        raise HTTPException(status_code=503, detail="AI not ready")

    prompt = (
        "A phishing check ran on the user's own phone. You cannot see the message "
        "or any link, and must not ask for them. The check reported:\n"
        f"- Prediction: {req.prediction}\n"
        f"- Risk score: {req.risk_score}%\n"
        f"- Signals: {', '.join(reasons) if reasons else 'none'}\n"
        f"- URL check: {url_flag}\n\n"
        "In 3-4 sentences, explain in plain English what this means, whether they "
        "are at risk, and what to do next."
    )
    try:
        text = await asyncio.get_event_loop().run_in_executor(
            None, lambda: assistant_instance.get_llm_response(prompt)
        )
    except Exception:
        text = "Could not generate AI explanation at this time."
    return {"ai_explanation": untrusted.guard_answer(text)}


@app.post("/api/security/wifi")
async def analyze_wifi(req: WifiRequest):
    """Assess Wi-Fi network security using the LLM."""
    if assistant_instance is None:
        raise HTTPException(status_code=503, detail="AI not ready")

    # The SSID identifies a place (home, workplace) and never reaches the LLM.
    # security_type is reduced to a closed set so no client string is interpolated.
    security_type = _WIFI_SECURITY_TYPES.get(req.security_type.strip().upper(), "Unknown")
    prompt = (
        f"A user is connected to a Wi-Fi network with these details:\n"
        f"- Security Type: {security_type}\n"
        f"- Is Public Hotspot: {req.is_public}\n\n"
        f"As a cybersecurity expert, assess the risk level of this network. "
        f"Reply in this exact format:\n"
        f"Risk Level: [SAFE / LOW / MEDIUM / HIGH]\n"
        f"Assessment: [2-3 sentences explaining the risk]\n"
        f"Action: [One specific thing the user should do right now]"
    )
    result = await asyncio.get_event_loop().run_in_executor(
        None, lambda: assistant_instance.get_llm_response(prompt)
    )
    return {"ssid": req.ssid, "security_type": req.security_type, "analysis": result}


@app.post("/api/security/device")
async def analyze_device(req: DeviceRequest):
    """Audit Android device security settings using the LLM."""
    if assistant_instance is None:
        raise HTTPException(status_code=503, detail="AI not ready")

    issues = []
    if req.usb_debugging:    issues.append("USB Debugging is ON")
    if req.unknown_sources:  issues.append("Install from Unknown Sources is ON")
    if req.developer_mode:   issues.append("Developer Mode is ON")
    if not req.screen_lock:  issues.append("No Screen Lock set")
    if not req.google_play_protect: issues.append("Google Play Protect is DISABLED")

    # Only the major Android version is used; the raw string can carry build
    # fingerprints and vendor detail, so it is never interpolated into the prompt.
    major = re.match(r"\s*(\d{1,2})\b", req.os_version)
    os_major = major.group(1) if major else "unknown"
    prompt = (
        f"Perform a security audit on this Android device:\n"
        f"- Android major version: {os_major}\n"
        f"- Security Issues Found: {', '.join(issues) if issues else 'None detected'}\n"
        f"- Screen Lock: {'Enabled' if req.screen_lock else 'DISABLED'}\n"
        f"- Google Play Protect: {'Enabled' if req.google_play_protect else 'DISABLED'}\n\n"
        f"Respond in this format:\n"
        f"Overall Security: [SECURE / AT RISK / CRITICAL]\n"
        f"Issues:\n- [list each issue with a one-line explanation]\n"
        f"Top Priority Fix: [the single most important thing to do first]"
    )
    analysis = await asyncio.get_event_loop().run_in_executor(
        None, lambda: assistant_instance.get_llm_response(prompt)
    )
    return {"issues_detected": issues, "issue_count": len(issues), "analysis": analysis}


@app.post("/api/security/apps")
async def audit_apps():
    """Retired. Kept only so old clients get a clear answer instead of a crash.

    This route used to forward app names, package IDs and permission sets to the
    LLM, which is exactly the payload the bounded channel exists to prevent. It
    now reads no body, builds no prompt and makes no LLM call.
    """
    return JSONResponse(
        status_code=410,
        content={
            "detail": "This endpoint has been removed. Detect on-device and "
                      "submit finding codes to /api/security/findings instead.",
            "use": "/api/security/findings",
        },
    )


# ─────────────────────────────────────────────────────────────────────────────
# FINDINGS ENDPOINT — privacy-preserving device advisory
# ─────────────────────────────────────────────────────────────────────────────
# Unlike the endpoints above, this one never receives device data. The client
# detects locally and submits canonical finding codes; everything sent onward to
# the LLM is built from the server-side registry, never from client input.
from findings import (                                          # noqa: E402
    GateError,
    REGISTRY,
    assert_no_leak,
    offline_advice,
    registry_summary,
    sanitize_batch,
)

_SEVERITY_RANK = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}

# A batch may carry up to 100 findings, but only the most severe few are worth
# an LLM call. Without this cap one request could fan out to 100 Groq calls.
MAX_AI_ENRICHMENT = 8


class FindingsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    findings: list
    want_ai: Optional[bool] = True
    schema_version: Optional[int] = None   # absent -> current version


def _build_advice_prompt(code: str, severity: str, facets: dict) -> str:
    """Construct the LLM prompt from REGISTRY data only.

    Note every value interpolated below originates server-side: `title` comes
    from the registry, `severity` from the registry, and `facets` have already
    passed the gate (closed-set values only). No client string reaches the LLM.
    """
    spec = REGISTRY[code]
    facet_text = ", ".join(f"{k}={v}" for k, v in sorted(facets.items())) or "none"
    return (
        f"An on-device security scan raised this finding:\n\n"
        f"Finding: {spec.title}\n"
        f"Severity: {severity}\n"
        f"Context: {facet_text}\n\n"
        f"You do not have access to the user's device or any of its data, and you "
        f"must not ask for any. Using only the finding above, reply in this format:\n"
        f"What this means: [2 sentences in plain language]\n"
        f"Do this now:\n- [step 1]\n- [step 2]\n- [step 3]\n"
        f"Urgency: [immediate / soon / when convenient]"
    )


async def _llm_with_semaphore(prompt: str) -> str:
    """Run an LLM call under the same concurrency cap as /api/chat.

    Without this the findings endpoint bypasses the Groq semaphore entirely and
    can push total in-flight calls past the free-tier limit.
    """
    await asyncio.wait_for(_llm_semaphore.acquire(), timeout=QUEUE_TIMEOUT_S)
    try:
        return await asyncio.get_event_loop().run_in_executor(
            None, lambda: assistant_instance.get_llm_response(prompt)
        )
    finally:
        _llm_semaphore.release()


@app.post("/api/security/findings")
async def analyze_findings(req: FindingsRequest, client_request: Request):
    """Turn on-device finding codes into remediation guidance.

    Offline playbooks are returned unconditionally, so the endpoint stays useful
    when the LLM is cold, rate-limited, or unavailable.
    """
    if req.schema_version not in (None, FINDINGS_SCHEMA_VERSION):
        raise HTTPException(status_code=400, detail="Unsupported schema_version.")

    try:
        accepted, rejected = sanitize_batch(req.findings)
    except GateError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Spend the AI budget on the most severe findings, not on arrival order.
    accepted.sort(key=lambda f: _SEVERITY_RANK.get(f.severity.value, 9))
    ai_budget = MAX_AI_ENRICHMENT if req.want_ai else 0

    results = []
    for finding in accepted:
        payload = finding.to_dict()

        # Independent re-check before anything crosses a network boundary.
        # sanitize_batch should make this unreachable; it runs anyway because a
        # silent regression here would break the product's core guarantee.
        try:
            assert_no_leak(payload)
        except GateError:
            _metrics["errors"] += 1
            logger.error("Privacy gate rejected an outbound payload for %s", finding.code)
            continue

        entry = {
            **payload,
            "title": REGISTRY[finding.code].title,
            "offline": offline_advice(finding),
            "ai": None,
        }

        if req.want_ai and assistant_instance is not None:
            cache_key = f"finding::{finding.cache_key()}"
            cached = await cache_manager.aget(cache_key)
            if cached:
                # Cache hits are free — they don't consume the AI budget.
                _metrics["cache_hits"] += 1
                entry["ai"] = cached
            elif ai_budget > 0:
                ai_budget -= 1
                prompt = _build_advice_prompt(
                    finding.code, finding.severity.value, finding.facets
                )
                try:
                    _metrics["llm_calls"] += 1
                    advice = untrusted.guard_answer(
                        await _llm_with_semaphore(prompt), finding
                    )
                    await cache_manager.aset(cache_key, advice)
                    entry["ai"] = advice
                except asyncio.TimeoutError:
                    _metrics["queue_timeouts"] += 1
                    logger.warning("LLM queue timeout for %s", finding.code)
                except Exception as e:
                    _metrics["errors"] += 1
                    logger.error("Advice generation failed for %s: %s", finding.code, e)
                    # Offline playbook already covers this finding.

        results.append(entry)

    worst = results[0]["sev"] if results else "none"

    return {
        "accepted": len(results),
        "rejected": len(rejected),
        "rejection_reasons": rejected[:10],
        "worst_severity": worst,
        "ai_enriched": sum(1 for r in results if r["ai"]),
        "findings": results,
    }


@app.get("/api/security/findings/registry")
async def findings_registry():
    """Published contract. Clients use this to validate codes before submitting,
    and it makes the privacy surface auditable by anyone."""
    return registry_summary()


@app.get("/api/security/findings/leakage")
async def findings_leakage():
    """Information capacity of the wire format, in bits, computed from the
    registry. Static for a given deployment, so clients may cache it."""
    return JSONResponse(content=leakage.leakage_table(),
                        headers={"Cache-Control": "public, max-age=3600"})
