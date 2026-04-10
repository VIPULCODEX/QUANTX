"""
app.py – Streamlit UI for QuantX AI Assistant
Run: streamlit run app.py
Dark Web / Matrix Theme with real-time feel
"""

import os
import sys
import time
import streamlit as st
from dotenv import load_dotenv

# Force UTF-8 encoding on Windows to prevent codec errors
os.environ["PYTHONIOENCODING"] = "utf-8"
if sys.stdout and hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass


# ── Load env vars first ──────────────────────────────────────────
load_dotenv()

# ── Page config (MUST be first Streamlit call) ───────────────────
st.set_page_config(
    page_title="QuantX AI",
    page_icon="🛡",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ════════════════════════════════════════════════════════════════
#  THEMES CONFIGURATION
# ════════════════════════════════════════════════════════════════
THEMES = {
    "QuantX Premium": { 
        "P": "#00FF9F",   # Primary Neon Green
        "S": "#00CFFF",   # Secondary Electric Blue
        "A": "#FF004D",   # Accent Pink/Red
        "AM": "#FFC857",  # Amber/Warning
        "DG": "#0B3D2E",  # Dark Green Tactical
        "BG": "#020202",  # Background
        "UBG": "rgba(0, 255, 159, 0.05)", 
        "BBG": "rgba(0, 207, 255, 0.05)",
        "T": "#E0E0E0" 
    }
}

if "theme" not in st.session_state:
    st.session_state.theme = "QuantX Premium"

# ════════════════════════════════════════════════════════════════
#  MATRIX / DARK-WEB CSS + CANVAS RAIN ANIMATION
# ════════════════════════════════════════════════════════════════
MATRIX_STYLE_BASE = """
<style>
/* ── Google Font ── */
@import url('https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Orbitron:wght@400;700;900&display=swap');
@import url('https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&display=swap');

/* ── Global Reset ── */
*, *::before, *::after { box-sizing: border-box; margin: 0; }

/* ── App background ── */
.stApp {
    background-color: #020202 !important;
    color: #E0E0E0 !important;
    font-family: 'Share Tech Mono', 'Noto Color Emoji', monospace !important;
}

/* ── Matrix canvas overlay ── */
#matrix-canvas {
    position: fixed;
    top: 0; left: 0;
    width: 100%; height: 100%;
    z-index: 0;
    opacity: 0.07;
    pointer-events: none;
}

/* ── All content above canvas ── */
.main .block-container {
    position: relative;
    z-index: 1;
    padding-top: 1rem !important;
    max-width: 1100px !important;
    margin: 0 auto !important;
}

/* ── Sidebar ── */
[data-testid="stSidebar"] {
    background-color: #030f03 !important;
    border-right: 1px solid #00ff4133 !important;
    overflow-x: hidden !important;
}
[data-testid="stSidebar"] > div {
    overflow-x: hidden !important;
}
[data-testid="stSidebar"] * {
    color: #00ff41 !important;
    font-family: 'Share Tech Mono', monospace !important;
}

/* ── Header title ── */
.cyber-header {
    text-align: center;
    padding: 1.2rem 0 0.5rem 0;
    font-family: 'Orbitron', monospace;
}
.cyber-header h1 {
    font-size: 2.2rem;
    font-weight: 900;
    color: #FFC857;
    text-shadow: 0 0 15px rgba(255, 200, 87, 0.7), 0 0 30px rgba(255, 200, 87, 0.3);
    letter-spacing: 6px;
    text-transform: uppercase;
    animation: neonPulse 3s infinite alternate;
}
@keyframes neonPulse {
    from { text-shadow: 0 0 10px rgba(255, 200, 87, 0.5); }
    to { text-shadow: 0 0 25px rgba(255, 200, 87, 0.8), 0 0 45px rgba(255, 200, 87, 0.4); }
}
.cyber-header p {
    color: #00cc33;
    font-size: 0.75rem;
    letter-spacing: 3px;
    margin-top: 0.3rem;
    font-family: 'Share Tech Mono', monospace;
}

/* ── Flicker animation ── */
@keyframes flicker {
    0%, 95%, 100% { opacity: 1; }
    96% { opacity: 0.85; }
    97% { opacity: 1; }
    98% { opacity: 0.7; }
    99% { opacity: 1; }
}

/* ── Scanline overlay ── */
.scanlines {
    position: fixed;
    top: 0; left: 0;
    width: 100%; height: 100%;
    background: repeating-linear-gradient(
        0deg,
        transparent,
        transparent 2px,
        rgba(0, 255, 65, 0.012) 2px,
        rgba(0, 255, 65, 0.012) 4px
    );
    pointer-events: none;
    z-index: 0;
}

/* ── Threat Indicator ── */
.threat-container {
    padding: 10px;
    background: rgba(11, 61, 46, 0.3);
    border: 1px solid rgba(0, 255, 159, 0.2);
    border-radius: 8px;
    margin-bottom: 20px;
}
.threat-bar {
    height: 10px;
    width: 100%;
    background: #1a1a1a;
    border-radius: 5px;
    overflow: hidden;
    margin-top: 8px;
    border: 1px solid rgba(255, 255, 255, 0.1);
}
.threat-fill {
    height: 100%;
    transition: width 0.5s ease-in-out, background 0.5s;
}

/* ── Radar ── */
.radar-box {
    width: 100%;
    display: flex;
    justify-content: center;
    padding: 10px 0 25px 0;
}
.radar {
    width: 120px;
    height: 120px;
    border-radius: 50%;
    border: 2px solid rgba(0, 255, 159, 0.4);
    position: relative;
    overflow: hidden;
    background: radial-gradient(circle, rgba(11, 61, 46, 0.5) 0%, transparent 70%);
}
.radar::before {
    content: '';
    position: absolute;
    top: 50%; left: 10%; right: 10%;
    height: 1px; background: rgba(0, 255, 159, 0.2);
}
.radar::after {
    content: '';
    position: absolute;
    top: 50%; left: 50%;
    width: 200%; height: 200%;
    background: conic-gradient(from 0deg, rgba(0, 255, 159, 0.3) 0%, transparent 25%);
    transform: translate(-50%, -50%);
    animation: rotate 4s linear infinite;
    pointer-events: none;
}
@keyframes rotate {
    from { transform: translate(-50%, -50%) rotate(0deg); }
    to { transform: translate(-50%, -50%) rotate(360deg); }
}

/* ── System Logs ── */
.log-container {
    background: rgba(0, 0, 0, 0.8) !important;
    border: 1px solid rgba(0, 255, 159, 0.2) !important;
    border-radius: 4px;
    padding: 10px;
    height: 180px;
    font-size: 0.7rem !important;
    font-family: 'Share Tech Mono', monospace !important;
    color: #00FF9F !important;
    overflow-y: hidden;
    display: flex;
    flex-direction: column-reverse;
    gap: 4px;
    box-shadow: inset 0 0 10px rgba(0, 255, 159, 0.1);
}
.log-line {
    border-left: 2px solid rgba(0, 255, 159, 0.3);
    padding-left: 8px;
    animation: logFadeIn 0.3s ease-out;
}
@keyframes logFadeIn {
    from { opacity: 0; transform: translateX(-5px); }
    to { opacity: 1; transform: translateX(0); }
}

/* ── Glassmorphism Utility ── */
.glass-card {
    background: rgba(10, 10, 20, 0.4) !important;
    backdrop-filter: blur(12px) !important;
    -webkit-backdrop-filter: blur(12px) !important;
    border: 1px solid rgba(0, 255, 159, 0.1) !important;
    border-radius: 12px !important;
}

/* ── Chat container ── */
.chat-container {
    display: flex;
    flex-direction: column;
    gap: 16px;
    margin-bottom: 1rem;
}

/* ── User message bubble ── */
.msg-user {
    align-self: flex-end;
    background: rgba(0, 207, 255, 0.08) !important;
    backdrop-filter: blur(8px);
    border: 1px solid rgba(0, 207, 255, 0.2) !important;
    border-radius: 12px 12px 0 12px;
    padding: 12px 18px;
    max-width: 85%;
    color: #00CFFF;
    font-family: 'Share Tech Mono', monospace;
    font-size: 0.9rem;
    box-shadow: 0 4px 15px rgba(0, 207, 255, 0.05);
    position: relative;
    transition: all 0.3s ease;
}
.msg-user::before {
    content: '> OPERATOR';
    display: block;
    color: rgba(0, 207, 255, 0.6);
    font-size: 0.65rem;
    font-weight: bold;
    letter-spacing: 2px;
    margin-bottom: 6px;
}

/* ── Assistant message bubble ── */
.msg-bot {
    align-self: flex-start;
    background: rgba(0, 255, 159, 0.05) !important;
    backdrop-filter: blur(8px);
    border: 1px solid rgba(0, 255, 159, 0.15) !important;
    border-left: 3px solid #00FF9F !important;
    border-radius: 12px 12px 12px 0;
    padding: 16px 22px;
    max-width: 90%;
    color: #E0E0E0;
    font-family: 'Share Tech Mono', monospace;
    font-size: 0.9rem;
    line-height: 1.6;
    box-shadow: 0 4px 20px rgba(0, 255, 159, 0.03);
    white-space: pre-wrap;
    word-wrap: break-word;
}
.msg-bot::before {
    content: '>> QUANTX_CORE v2.0';
    display: block;
    color: #00FF9F;
    font-size: 0.65rem;
    font-weight: bold;
    letter-spacing: 2px;
    margin-bottom: 10px;
}

/* ── News card ── */
.news-card {
    background: rgba(0, 207, 255, 0.03) !important;
    backdrop-filter: blur(6px);
    border: 1px solid rgba(0, 207, 255, 0.1) !important;
    border-top: 2px solid #00CFFF !important;
    border-radius: 8px;
    padding: 16px 20px;
    margin: 12px 0;
    color: #E0E0E0;
    font-family: 'Share Tech Mono', monospace;
    font-size: 0.88rem;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
}

/* ── Alert / attack type card ── */
.attack-card {
    background: rgba(255, 0, 77, 0.05) !important;
    backdrop-filter: blur(8px);
    border: 1px solid rgba(255, 0, 77, 0.2) !important;
    border-left: 4px solid #FF004D !important;
    border-radius: 8px;
    padding: 16px 20px;
    color: #FFC0D0;
    font-family: 'Share Tech Mono', monospace;
    font-size: 0.9rem;
    box-shadow: 0 4px 15px rgba(255, 0, 77, 0.05);
}

/* ── Status badges ── */
.badge {
    display: inline-block;
    padding: 2px 10px;
    border-radius: 3px;
    font-size: 0.7rem;
    letter-spacing: 2px;
    font-family: 'Share Tech Mono', monospace;
    text-transform: uppercase;
}
.badge-rag   { background: #001a08; color: #00ff41; border: 1px solid #00ff41; }
.badge-news  { background: #00001a; color: #4d9fff; border: 1px solid #4d9fff; }
.badge-alert { background: #1a0000; color: #ff4d00; border: 1px solid #ff4d00; }

/* ── Input box ── */
.stTextInput > div > div > input,
.stChatInput textarea {
    background-color: rgba(10, 10, 20, 0.6) !important;
    color: #00FF9F !important;
    border: 1px solid rgba(0, 255, 159, 0.2) !important;
    border-radius: 8px !important;
}

[data-testid="stChatInput"] {
    background-color: rgba(10, 10, 20, 0.6) !important;
    border: 1px solid rgba(0, 255, 159, 0.2) !important;
    border-radius: 12px !important;
}
[data-testid="stChatInput"] button {
    background-color: #00FF9F !important;
    color: #020202 !important;
}

/* ── Buttons ── */
.stButton > button {
    background-color: transparent !important;
    color: #00FF9F !important;
    border: 1px solid #00FF9F !important;
    border-radius: 6px !important;
}
.stButton > button:hover {
    background-color: #00FF9F !important;
    color: #020202 !important;
    box-shadow: 0 0 20px rgba(0, 255, 159, 0.6) !important;
}
.stButton > button:hover * {
    color: #000000 !important;
}


/* ── Spinner ── */
.stSpinner > div {
    border-color: #00ff41 transparent transparent transparent !important;
}

/* ── Divider ── */
hr {
    border-color: #00ff4122 !important;
    margin: 1rem 0 !important;
}

/* ── Sidebar ── */
.sidebar-title {
    font-family: 'Orbitron', monospace;
    color: #00FF9F;
    font-size: 0.9rem;
    letter-spacing: 3px;
    text-transform: uppercase;
    text-shadow: 0 0 10px rgba(0, 255, 159, 0.5);
    padding: 0.5rem 0;
}

/* ── Status indicator ── */
.status-dot {
    display: inline-block;
    width: 8px; height: 8px;
    border-radius: 50%;
    background: #00ff41;
    box-shadow: 0 0 6px #00ff41;
    animation: pulse 2s infinite;
    margin-right: 6px;
}
@keyframes pulse {
    0%, 100% { opacity: 1; box-shadow: 0 0 6px #00ff41; }
    50% { opacity: 0.4; box-shadow: 0 0 2px #00ff41; }
}

/* ── Terminal-style divider ── */
.term-divider {
    color: #00ff4144;
    font-size: 0.75rem;
    letter-spacing: 1px;
    text-align: center;
    padding: 4px 0;
    font-family: 'Share Tech Mono', monospace;
}

/* ── Quick query chips ── */
.chip {
    display: inline-block;
    background: #001a08;
    border: 1px solid #00ff4133;
    border-radius: 3px;
    padding: 3px 10px;
    color: #00cc33;
    font-size: 0.75rem;
    font-family: 'Share Tech Mono', monospace;
    margin: 2px;
    cursor: pointer;
}

/* ── Metric cards in sidebar ── */
[data-testid="stMetric"] {
    background: #000d05 !important;
    border: 1px solid #00ff4122 !important;
    border-radius: 4px !important;
    padding: 0.5rem !important;
}
[data-testid="stMetricLabel"] { color: #00cc33 !important; font-size: 0.7rem !important; }
[data-testid="stMetricValue"] { color: #00ff41 !important; font-size: 1.2rem !important; }

/* ── Hide Streamlit branding ── */
#MainMenu, footer { visibility: hidden; }
header { background-color: transparent !important; }
.stDeployButton { display: none !important; }

/* ── Scrollbar ── */
::-webkit-scrollbar { width: 4px; }
::-webkit-scrollbar-track { background: #000; }
::-webkit-scrollbar-thumb { background: #00ff4144; border-radius: 2px; }
::-webkit-scrollbar-thumb:hover { background: #00ff41; }

/* ── Responsive adjustments ── */
@media (max-width: 768px) {
    .cyber-header h1 {
        font-size: 1.5rem !important;
        letter-spacing: 2px !important;
    }
    .cyber-header p {
        font-size: 0.65rem !important;
        letter-spacing: 1px !important;
    }
    .main .block-container {
        padding-left: 0.5rem !important;
        padding-right: 0.5rem !important;
        padding-top: 0.5rem !important;
    }
    .msg-user {
        max-width: 95% !important;
        padding: 8px 12px !important;
    }
    .msg-bot, .attack-card, .news-card {
        max-width: 100% !important;
        padding: 10px 14px !important;
        font-size: 0.8rem !important;
    }
    .sidebar-title {
        font-size: 0.8rem !important;
        letter-spacing: 1.5px !important;
    }
    [data-testid="stMetricValue"] {
        font-size: 1rem !important;
    }
}
</style>

<!-- Grid Overlay -->
<div class="grid-overlay"></div>

<style>
.grid-overlay {
    position: fixed;
    top: 0; left: 0;
    width: 100%; height: 100%;
    z-index: 0;
    background-size: 40px 40px;
    background-image: 
        linear-gradient(to right, rgba(0, 255, 159, 0.05) 1px, transparent 1px),
        linear-gradient(to bottom, rgba(0, 255, 159, 0.05) 1px, transparent 1px);
    pointer-events: none;
}
</style>

<canvas id="grid-canvas"></canvas>

<script>
(function() {
    const canvas = document.getElementById('grid-canvas');
    const ctx = canvas.getContext('2d');
    
    function resize() {
        canvas.width  = window.innerWidth;
        canvas.height = window.innerHeight;
    }
    resize();
    window.addEventListener('resize', resize);
    
    let offset = 0;
    function draw() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.strokeStyle = 'rgba(0, 255, 159, 0.15)';
        const vanishingPointY = canvas.height * 0.4;
        const gridSpacing = 60;
        
        // Vertical lines
        for (let i = -30; i <= 30; i++) {
            ctx.beginPath();
            ctx.moveTo(canvas.width / 2, vanishingPointY);
            ctx.lineTo(canvas.width / 2 + (i * gridSpacing * 5), canvas.height);
            ctx.stroke();
        }
        // Horizontal lines
        offset += 1.2;
        if (offset > gridSpacing) offset = 0;
        for (let i = 0; i < 20; i++) {
            const screenY = vanishingPointY + (Math.pow(1.5, i) * (10 + offset));
            if (screenY > canvas.height) break;
            const alpha = Math.min(1.0, (screenY - vanishingPointY) / 300);
            ctx.strokeStyle = `rgba(0, 255, 159, ${alpha * 0.2})`;
            ctx.beginPath();
            ctx.moveTo(0, screenY);
            ctx.lineTo(canvas.width, screenY);
            ctx.stroke();
        }
        requestAnimationFrame(draw);
    }
    draw();
})();
</script>
"""

# ─────────────────────────────────────────────────────────────
#  THEME STYLE INJECTION
# ─────────────────────────────────────────────────────────────
def get_theme_style(theme_name):
    theme = THEMES[theme_name]
    style = MATRIX_STYLE_BASE
    # Replace the base color placeholders with theme-specific values
    style = style.replace("#00FF9F", theme["P"]).replace("#00CFFF", theme["S"])
    style = style.replace("rgba(0, 255, 159, 0.05)", theme["UBG"]).replace("rgba(0, 207, 255, 0.05)", theme["BBG"])
    style = style.replace("#E0E0E0", theme["T"]).replace("#FF004D", theme["A"])
    style = style.replace("#020202", theme["BG"])
    return style

st.markdown(get_theme_style(st.session_state.theme), unsafe_allow_html=True)

# ════════════════════════════════════════════════════════════════
#  IMPORTS (after streamlit setup)
# ════════════════════════════════════════════════════════════════
from config import GROQ_API_KEY, NEWS_API_KEY, TOP_K

# ════════════════════════════════════════════════════════════════
#  SESSION STATE INIT
# ════════════════════════════════════════════════════════════════
if "messages" not in st.session_state:
    st.session_state.messages = []         # chat history
if "assistant" not in st.session_state:
    st.session_state.assistant = None      # assistant object
if "pipeline_ready" not in st.session_state:
    st.session_state.pipeline_ready = False
if "top_k" not in st.session_state:
    st.session_state.top_k = TOP_K
if "query_count" not in st.session_state:
    st.session_state.query_count = 0
if "news_count" not in st.session_state:
    st.session_state.news_count = 0
if "logs" not in st.session_state:
    st.session_state.logs = ["[SYSTEM] Initializing tactical interface...", "[INFO] Secure connection established."]
if "threat_level" not in st.session_state:
    st.session_state.threat_level = 15  # Percent (Low)

def add_log(msg: str):
    """Add a new timestamped log to the session state logs."""
    import datetime
    timestamp = datetime.datetime.now().strftime("%H:%M:%S")
    st.session_state.logs.insert(0, f"[{timestamp}] {msg}")
    st.session_state.logs = st.session_state.logs[:15]  # Keep last 15
if "show_animation" not in st.session_state:
    st.session_state.show_animation = "Matrix (Green)"

# ════════════════════════════════════════════════════════════════
#  THEME ANIMATION INJECTION
# ════════════════════════════════════════════════════════════════
if st.session_state.show_animation:
    import streamlit.components.v1 as components
    theme_name = st.session_state.show_animation
    js_code = f"""
    <script>
        const overlay = window.parent.document.createElement("div");
        overlay.id = "theme-anim-overlay";
        Object.assign(overlay.style, {{
            position: 'fixed', top: '0', left: '0', width: '100vw', height: '100vh',
            zIndex: '999999', pointerEvents: 'none', overflow: 'hidden',
            backgroundColor: 'rgba(0,0,0,0.5)', transition: 'opacity 1.5s ease-out'
        }});
        window.parent.document.body.appendChild(overlay);

        function createParticle(content, cssProps, keyframes, duration) {{
            const p = window.parent.document.createElement("div");
            p.innerHTML = content;
            Object.assign(p.style, {{ position: 'absolute', ...cssProps }});
            overlay.appendChild(p);
            p.animate(keyframes, {{ duration: duration, easing: 'ease-out', fill: 'forwards' }});
        }}

        const chars = '01アイウエオカキクケコサシスセソタチツテトナニヌネノABCDEF<>+=/*';
        const numColumns = 60;
        for(let i=0; i<numColumns; i++) {{
            let colStr = '';
            const length = 25 + Math.floor(Math.random() * 35);
            for(let j=0; j<length; j++) {{
                colStr += chars[Math.floor(Math.random() * chars.length)] + '<br>';
            }}
            
            const isFalling = (i % 2 === 0);
            const startY = isFalling ? '-120vh' : '120vh';
            const endY = isFalling ? '240vh' : '-240vh'; 
            
            createParticle(colStr, {{ 
                left: (i * (100 / numColumns)) + '%', 
                top: startY, 
                color: '#00ff41', 
                fontFamily: '"Share Tech Mono", monospace', 
                fontSize: (0.8 + Math.random()*0.8) + 'rem', 
                lineHeight: '1.0',
                textAlign: 'center',
                textShadow: '0 0 8px #00ff41, 0 0 15px #00cc33',
                opacity: 0.5 + Math.random()*0.5
            }}, [
                {{ transform: 'translateY(0)' }},
                {{ transform: `translateY(${{endY}})` }}
            ], 4000 + Math.random()*2000);
        }}

        setTimeout(() => {{
            overlay.style.opacity = '0';
            setTimeout(() => overlay.remove(), 1500);
        }}, 5000);
    </script>
    """
    components.html(js_code, height=0, width=0)
    st.session_state.show_animation = None


# ════════════════════════════════════════════════════════════════
#  PIPELINE LOADER (cached across reruns)
# ════════════════════════════════════════════════════════════════
@st.cache_resource(show_spinner=False)
def load_pipeline(top_k: int):
    """Load RAG pipeline once and cache it. Reuses FAISS index if available."""
    from rag_pipeline import RAGPipeline
    from assistant import CybersecurityAssistant

    rag = RAGPipeline()
    rag.initialize()
    retriever = rag.get_retriever(k=top_k)
    assistant = CybersecurityAssistant(retriever)
    return assistant, rag


# ════════════════════════════════════════════════════════════════
#  HELPERS
# ════════════════════════════════════════════════════════════════
def detect_message_type(query: str, response: str) -> str:
    """Classify the response type for badge display."""
    q = query.lower()
    news_words = ["today", "recent", "latest", "news", "incident", "breach", "happened", "current"]
    if any(w in q for w in news_words):
        return "news"
    attack_words = ["attack type:", "what to do:", "explanation:"]
    if any(w in response.lower() for w in attack_words):
        return "alert"
    return "rag"


def stream_text(text: str, placeholder, delay: float = 0.005):
    """Simulate smooth streaming/typewriter effect for bot responses."""
    displayed = ""
    # Stream in small groups to reduce flicker and improve performance
    chunk_size = 2
    for i in range(0, len(text), chunk_size):
        displayed += text[i:i+chunk_size]
        placeholder.markdown(
            f'<div class="msg-bot">{displayed}▌</div>',
            unsafe_allow_html=True
        )
        time.sleep(delay)
    # Final render without cursor
    placeholder.markdown(
        f'<div class="msg-bot">{displayed}</div>',
        unsafe_allow_html=True
    )


def render_message(role: str, content: str, msg_type: str = "rag"):
    """Render a single chat message."""
    if role == "user":
        st.markdown(f'<div class="msg-user">{content}</div>', unsafe_allow_html=True)
    else:
        badge_map = {
            "rag":   '<span class="badge badge-rag">KNOWLEDGE BASE</span>',
            "news":  '<span class="badge badge-news">LIVE INTEL</span>',
            "alert": '<span class="badge badge-alert">THREAT DETECTED</span>',
        }
        badge = badge_map.get(msg_type, badge_map["rag"])
        css_class = "attack-card" if msg_type == "alert" else "msg-bot"
        st.markdown(
            f'{badge}<br><div class="{css_class}">{content}</div>',
            unsafe_allow_html=True
        )


# ════════════════════════════════════════════════════════════════
#  SIDEBAR
# ════════════════════════════════════════════════════════════════
with st.sidebar:
    st.markdown(f'<div class="sidebar-title">🛡 QUANTX TACTICAL</div>', unsafe_allow_html=True)
    
    # --- THREAT LEVEL ---
    level = st.session_state.threat_level
    color = "#00FF9F" if level < 30 else ("#FFC857" if level < 60 else "#FF004D")
    label = "LOW" if level < 30 else ("ELEVATED" if level < 60 else "CRITICAL")
    
    st.markdown(f"""
    <div class="threat-container">
        <div style="display:flex; justify-content:space-between; font-size:0.7rem; color:{color}; font-weight:bold;">
            <span>THREAT LEVEL</span>
            <span>{label}</span>
        </div>
        <div class="threat-bar">
            <div class="threat-fill" style="width:{level}%; background:{color}; box-shadow:0 0 10px {color}77;"></div>
        </div>
    </div>
    """, unsafe_allow_html=True)

    # --- RADAR ---
    st.markdown('<div class="radar-box"><div class="radar"></div></div>', unsafe_allow_html=True)

    # --- STATUS BAR ---
    if st.session_state.pipeline_ready:
        st.markdown(
            '<div style="text-align:center; padding-bottom:10px;"><span class="status-dot"></span><small style="color:#00FF9F">SYSTEM ONLINE</small></div>',
            unsafe_allow_html=True
        )

    # --- STATS ---
    col1, col2 = st.columns(2)
    with col1:
        st.metric("Queries", st.session_state.query_count)
    with col2:
        st.metric("News Intel", st.session_state.news_count)

    st.markdown("---")
    st.markdown('<div class="sidebar-title">// SYSTEM LOGS</div>', unsafe_allow_html=True)
    
    # --- LOGS ---
    log_html = "".join([f'<div class="log-line">{log}</div>' for log in st.session_state.logs])
    st.markdown(f'<div class="log-container">{log_html}</div>', unsafe_allow_html=True)

    st.markdown("---")
    st.markdown('<div class="sidebar-title">// SETTINGS</div>', unsafe_allow_html=True)

    # Top-K slider
    new_k = st.slider(
        "Retrieval Depth (top-k)",
        min_value=1, max_value=7,
        value=st.session_state.top_k,
        help="Number of knowledge base chunks to retrieve"
    )
    if new_k != st.session_state.top_k:
        st.session_state.top_k = new_k
        st.cache_resource.clear()
        st.session_state.pipeline_ready = False
        st.session_state.assistant = None
        st.rerun()

    # Streaming toggle
    streaming = st.toggle("Typewriter Effect", value=True)
    
    # RAG toggle
    use_rag = st.toggle("Enable RAG (Knowledge Base)", value=True)

    st.markdown("---")
    st.markdown('<div class="sidebar-title">// QUICK INTEL</div>', unsafe_allow_html=True)

    quick_queries = [
        "What is phishing?",
        "How does ransomware work?",
        "Explain SQL injection",
        "What is a DDoS attack?",
        "I clicked a suspicious link",
        "Latest cyber news",
    ]

    for qq in quick_queries:
        if st.button(f"> {qq}", key=f"quick_{qq}", use_container_width=True):
            st.session_state["pending_query"] = qq

    st.markdown("---")
    if st.button("// CLEAR TERMINAL", use_container_width=True):
        st.session_state.messages = []
        st.session_state.query_count = 0
        st.session_state.news_count = 0
        st.rerun()

    st.markdown("---")


# ════════════════════════════════════════════════════════════════
#  HEADER
# ════════════════════════════════════════════════════════════════
st.markdown("""
<div class="cyber-header">
    <h1>🛡 QUANTX AI</h1>
    <p>// REAL-TIME THREAT INTELLIGENCE & CYBERSECURITY ADVISOR //</p>
</div>
""", unsafe_allow_html=True)
st.markdown('<div class="term-divider">━━━━━━━━━━━━━━━━━━ SECURE CHANNEL ESTABLISHED ━━━━━━━━━━━━━━━━━━</div>', unsafe_allow_html=True)


# ════════════════════════════════════════════════════════════════
#  PIPELINE INIT
# ════════════════════════════════════════════════════════════════
if not GROQ_API_KEY:
    st.markdown("""
    <div class="attack-card">
    <b>[ERROR] GROQ_API_KEY not found.</b><br><br>
    Add your key to the <code>.env</code> file:<br>
    <code>GROQ_API_KEY=your_key_here</code><br><br>
    Get a free key at: https://console.groq.com/keys
    </div>
    """, unsafe_allow_html=True)
    st.stop()

if not st.session_state.pipeline_ready:
    with st.spinner("// INITIALIZING NEURAL CORE... LOADING KNOWLEDGE BASE..."):
        try:
            assistant, rag = load_pipeline(st.session_state.top_k)
            st.session_state.assistant = assistant
            st.session_state.pipeline_ready = True
        except ValueError as e:
            st.markdown(f"""
            <div class="attack-card">
            <b>[CRITICAL] Knowledge base error:</b><br>{str(e)}<br><br>
            Add PDF or TXT files to the <code>data/</code> folder and restart.
            </div>
            """, unsafe_allow_html=True)
            st.stop()
        except Exception as e:
            st.markdown(f"""
            <div class="attack-card">
            <b>[ERROR] Initialization failed:</b><br>{str(e)}
            </div>
            """, unsafe_allow_html=True)
            st.stop()

    st.rerun()  # Refresh to show ONLINE status


# ════════════════════════════════════════════════════════════════
#  CHAT HISTORY DISPLAY
# ════════════════════════════════════════════════════════════════
tab1, tab2 = st.tabs(["💬 Chat & Intel", "🔍 System Analysis"])

with tab1:
    if not st.session_state.messages:
        st.markdown("""
        <div class="msg-bot" style="border-left-color:#4d9fff; color:#b3d1ff;">
        SYSTEM READY. Welcome, operator.<br><br>
        I am your cybersecurity intelligence assistant. I can:<br>
        — Explain any cybersecurity attack or concept<br>
        — Identify attack types from your scenario descriptions<br>
        — Suggest immediate protective actions<br>
        — Fetch real-time cybersecurity news & incidents<br><br>
        <span style="color:#00ff41">Type your query below or select from the sidebar.</span>
        </div>
        """, unsafe_allow_html=True)
    else:
        st.markdown('<div class="chat-container">', unsafe_allow_html=True)
        for msg in st.session_state.messages:
            render_message(msg["role"], msg["content"], msg.get("type", "rag"))
        st.markdown('</div>', unsafe_allow_html=True)

    st.markdown('<div class="term-divider">──────────────────────────────────────────────</div>', unsafe_allow_html=True)


    # ════════════════════════════════════════════════════════════════
    #  CHAT INPUT
    # ════════════════════════════════════════════════════════════════
    # Handle quick query buttons from sidebar
    if "pending_query" in st.session_state:
        user_input = st.session_state.pop("pending_query")
    else:
        user_input = st.chat_input("// ENTER QUERY — describe a scenario, ask a question, or request news...")

    if user_input:
        assistant = st.session_state.assistant
        st.session_state.query_count += 1
        
        # Threat level logic (random fluctuation + increase on specific keywords)
        import random
        st.session_state.threat_level = min(95, max(10, st.session_state.threat_level + random.randint(-5, 8)))
        if any(w in user_input.lower() for w in ["hack", "attack", "breach", "malware", "ransomware"]):
            st.session_state.threat_level = min(100, st.session_state.threat_level + 15)
            add_log(f"ALERT: Suspicious pattern detected in query: {user_input[:20]}...")
        else:
            add_log(f"ANALYZING: {user_input[:30]}...")

        # Store user message
        st.session_state.messages.append({"role": "user", "content": user_input, "type": "user"})
        render_message("user", user_input)

        # Determine type
        news_words = ["today", "recent", "latest", "news", "incident", "breach", "happened", "current"]
        is_news = any(w in user_input.lower() for w in news_words)

        # Show thinking indicator
        st.markdown('<div class="term-divider">// PROCESSING QUERY...</div>', unsafe_allow_html=True)

        with st.spinner("// SCANNING KNOWLEDGE MATRIX..." if use_rag else "// PROCESSING RESPONSE (LLM ONLY)..."):
            try:
                response = assistant.respond(user_input, use_rag=use_rag)
            except Exception as e:
                response = f"[ERROR] Query failed: {str(e)}\n\nIf this is a quota error, please wait or use a new API key."

        # Determine message type for display
        msg_type = detect_message_type(user_input, response)

        # Store assistant message
        st.session_state.messages.append({
            "role": "assistant",
            "content": response,
            "type": msg_type
        })

        # Update counters
        st.session_state.query_count += 1
        if is_news:
            st.session_state.news_count += 1

        # Render response
        if streaming:
            placeholder = st.empty()
            stream_text(response, placeholder, delay=0.006)
            # Replace with proper render after streaming
            placeholder.empty()

        render_message("assistant", response, msg_type)

        st.rerun()

with tab2:
    st.markdown('<div class="sidebar-title">// SYSTEM VULNERABILITY SCAN</div>', unsafe_allow_html=True)
    st.markdown("<p style='color:#00cc33; font-size: 0.85rem; font-family: \"Share Tech Mono\", monospace;'>Enter your system details to receive a static vulnerability analysis without executing local system scans. This keeps your device fully private and runs smoothly via the AI CPU pipeline.</p>", unsafe_allow_html=True)
    
    with st.form("sys_analysis_form"):
        os_val = st.text_input("Operating System", placeholder="e.g., Windows 10, macOS Sonoma, Ubuntu 22.04")
        browser_val = st.text_input("Primary Browser", placeholder="e.g., Chrome v120, Firefox, Safari")
        av_val = st.text_input("Antivirus / Security Software", placeholder="e.g., Windows Defender, None")
        activity_val = st.text_area("Recent Suspicious Activity", placeholder="e.g., 'Computer runs exceptionally slow, weird popups, missing files...'")
        
        analyze_btn = st.form_submit_button("Run Analysis")
        
    if analyze_btn:
        if not os_val or not browser_val:
            st.error("Please provide at least your Operating System and Browser.")
        else:
            with st.spinner("// ANALYZING SYSTEM PARAMETERS..."):
                analysis_result = st.session_state.assistant.analyze_system(os_val, browser_val, av_val, activity_val)
                st.markdown(f'<div class="msg-bot" style="border-left-color:#ff4d00;">{analysis_result}</div>', unsafe_allow_html=True)



