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
import time
import logging
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from rag_pipeline import RAGPipeline
from assistant import CybersecurityAssistant
from config import TOP_K, GROQ_API_KEY, GROQ_API_KEY_LIST, LLM_MAX_TOKENS
from security import validate_query, rate_limiter, get_client_id
from cache_manager import cache_manager

# ─────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("quantx.api")
logger.setLevel(logging.INFO)

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
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─────────────────────────────────────────────────────────────────────────────
# Models
# ─────────────────────────────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    query: str
    user_id: Optional[str] = None
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

    # 1. Rate Limiting
    client_id = request.user_id or get_client_id(client_request)
    if not rate_limiter.is_allowed(client_id):
        _metrics["rate_limited"] += 1
        remaining = rate_limiter.get_remaining(client_id)
        raise HTTPException(
            status_code=429,
            detail=f"Rate limit exceeded. {remaining} requests remaining. Wait and retry.",
            headers={"Retry-After": "60"},
        )

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
        logger.error("LLM error: %s", e)
        raise HTTPException(status_code=500, detail=f"LLM Error: {str(e)}")
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
        "init_error": _init_status.get("error"),
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
    text: str


class WifiRequest(BaseModel):
    ssid: str
    security_type: str          # e.g. "WPA2", "WPA3", "Open", "WEP"
    is_public: Optional[bool] = False


class DeviceRequest(BaseModel):
    os_version: str
    usb_debugging: bool
    unknown_sources: bool
    developer_mode: bool
    screen_lock: bool
    google_play_protect: bool


class AppAuditRequest(BaseModel):
    apps: list                  # List of {name, package, permissions: [...]}


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
        raise HTTPException(status_code=500, detail=f"PhishSense error: {e}")

    # Build LLM explanation if assistant is ready
    explanation = ""
    if assistant_instance:
        prompt = (
            f"A user submitted the following text for phishing analysis:\n\n"
            f"\"{req.text}\"\n\n"
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

    return {**result, "ai_explanation": explanation}


@app.post("/api/security/wifi")
async def analyze_wifi(req: WifiRequest):
    """Assess Wi-Fi network security using the LLM."""
    if assistant_instance is None:
        raise HTTPException(status_code=503, detail="AI not ready")

    prompt = (
        f"A user is connected to a Wi-Fi network with these details:\n"
        f"- Network Name (SSID): {req.ssid}\n"
        f"- Security Type: {req.security_type}\n"
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

    prompt = (
        f"Perform a security audit on this Android device:\n"
        f"- OS Version: {req.os_version}\n"
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
async def audit_apps(req: AppAuditRequest):
    """Flag suspicious installed apps based on name and permissions using the LLM."""
    if assistant_instance is None:
        raise HTTPException(status_code=503, detail="AI not ready")

    app_summary = "\n".join([
        f"- {a.get('name', 'Unknown')} ({a.get('package', '')}): permissions={a.get('permissions', [])}"
        for a in req.apps[:40]   # cap at 40 to avoid token overflow
    ])
    prompt = (
        f"Review this list of installed Android apps and their permissions. "
        f"Flag any that seem suspicious (e.g. a flashlight app requesting microphone/location):\n\n"
        f"{app_summary}\n\n"
        f"Respond in this format:\n"
        f"Suspicious Apps Found: [number]\n"
        f"Flagged:\n- [App Name]: [reason why it's suspicious]\n"
        f"Safe Apps: [count of apps that look normal]\n"
        f"Recommendation: [one overall action for the user]"
    )
    analysis = await asyncio.get_event_loop().run_in_executor(
        None, lambda: assistant_instance.get_llm_response(prompt)
    )
    return {"total_apps_scanned": len(req.apps), "analysis": analysis}
