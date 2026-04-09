"""
app.py – Streamlit UI for Cybersecurity Friend AI Assistant
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
    page_title="CyberFriend AI",
    page_icon="🛡",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ════════════════════════════════════════════════════════════════
#  THEMES CONFIGURATION
# ════════════════════════════════════════════════════════════════
THEMES = {
    "Matrix (Green)": { "P": "#00ff41", "S": "#00cc33", "UBG": "#00140a", "BBG": "#000d05", "T": "#b3ffcc", "A": "#ff4d00", "AT": "#ffb380", "CBG": "#030f03", "BG": "#000000" }
}

if "theme" not in st.session_state:
    st.session_state.theme = "Matrix (Green)"

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
    background-color: #000000 !important;
    color: #00ff41 !important;
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
    font-size: 2rem;
    font-weight: 900;
    color: #00ff41;
    text-shadow: 0 0 20px #00ff41, 0 0 40px #00ff4177, 0 0 80px #00ff4133;
    letter-spacing: 4px;
    text-transform: uppercase;
    animation: flicker 4s infinite;
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

/* ── Chat container ── */
.chat-container {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-bottom: 1rem;
}

/* ── User message bubble ── */
.msg-user {
    align-self: flex-end;
    background: #00140a;
    border: 1px solid #00ff4166;
    border-radius: 6px 0 6px 6px;
    padding: 10px 16px;
    max-width: 80%;
    color: #00ff41;
    font-family: 'Share Tech Mono', monospace;
    font-size: 0.88rem;
    box-shadow: 0 0 10px #00ff4122;
    position: relative;
}
.msg-user::before {
    content: '> YOU';
    display: block;
    color: #00ff4199;
    font-size: 0.7rem;
    letter-spacing: 2px;
    margin-bottom: 5px;
}

/* ── Assistant message bubble ── */
.msg-bot {
    align-self: flex-start;
    background: #000d05;
    border: 1px solid #00cc3355;
    border-left: 3px solid #00ff41;
    border-radius: 0 6px 6px 6px;
    padding: 14px 18px;
    max-width: 90%;
    color: #b3ffcc;
    font-family: 'Share Tech Mono', monospace;
    font-size: 0.87rem;
    line-height: 1.65;
    box-shadow: 0 0 18px #00ff4111, inset 0 0 30px #00ff4106;
    white-space: pre-wrap;
    word-wrap: break-word;
}
.msg-bot::before {
    content: '>> AI_SHIELD v1.0';
    display: block;
    color: #00ff41;
    font-size: 0.7rem;
    letter-spacing: 2px;
    margin-bottom: 8px;
    text-shadow: 0 0 8px #00ff41;
}

/* ── News card ── */
.news-card {
    background: #000a00;
    border: 1px solid #00ff4133;
    border-top: 2px solid #00ff41;
    border-radius: 4px;
    padding: 14px 18px;
    margin: 8px 0;
    color: #b3ffcc;
    font-family: 'Share Tech Mono', monospace;
    font-size: 0.85rem;
    line-height: 1.6;
    box-shadow: 0 0 12px #00ff4111;
}

/* ── Alert / attack type card ── */
.attack-card {
    background: #0a0000;
    border: 1px solid #ff4d0044;
    border-left: 3px solid #ff4d00;
    border-radius: 4px;
    padding: 14px 18px;
    color: #ffb380;
    font-family: 'Share Tech Mono', monospace;
    font-size: 0.87rem;
    line-height: 1.7;
    box-shadow: 0 0 12px #ff4d0022;
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
    background-color: #000d05 !important;
    color: #00ff41 !important;
    border: 1px solid #00ff4155 !important;
    border-radius: 4px !important;
    font-family: 'Share Tech Mono', monospace !important;
    font-size: 0.9rem !important;
    caret-color: #00ff41 !important;
}
.stTextInput > div > div > input:focus,
.stChatInput textarea:focus {
    border-color: #00ff41 !important;
    box-shadow: 0 0 10px #00ff4133 !important;
}

/* ── Chat input wrapper styling ── */
[data-testid="stChatInput"] {
    background-color: #000d05 !important;
    border: 1px solid #00ff4144 !important;
    border-radius: 6px !important;
}
[data-testid="stChatInput"] textarea {
    background-color: transparent !important;
    color: #00ff41 !important;
}
[data-testid="stChatInput"] button {
    background-color: #003311 !important;
    color: #00ff41 !important;
    border: 1px solid #00ff4155 !important;
}
[data-testid="stChatInput"] button:hover {
    background-color: #00ff41 !important;
    color: #000 !important;
}

/* ── Buttons ── */
.stButton > button {
    background-color: #000d05 !important;
    color: #00ff41 !important;
    border: 1px solid #00ff4166 !important;
    border-radius: 4px !important;
    font-family: 'Share Tech Mono', monospace !important;
    font-size: 0.8rem !important;
    letter-spacing: 1px !important;
    transition: all 0.2s !important;
}
.stButton > button:hover {
    background-color: #00ff41 !important;
    color: #000 !important;
    box-shadow: 0 0 15px #00ff4155 !important;
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

/* ── Sidebar headers ── */
.sidebar-title {
    font-family: 'Orbitron', monospace;
    color: #00ff41;
    font-size: 0.9rem;
    letter-spacing: 3px;
    text-transform: uppercase;
    text-shadow: 0 0 10px #00ff41;
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
</style>

<!-- Scanline overlay -->
<div class="scanlines"></div>

<!-- Matrix Rain Canvas -->
<canvas id="matrix-canvas"></canvas>

<script>
(function() {
    const canvas = document.getElementById('matrix-canvas');
    const ctx = canvas.getContext('2d');
    
    function resize() {
        canvas.width  = window.innerWidth;
        canvas.height = window.innerHeight;
    }
    resize();
    window.addEventListener('resize', resize);
    
    const chars = '01アイウエオカキクケコサシスセソタチツテトナニヌネノABCDEF<>{}[]|/\\';
    const fontSize = 13;
    let cols = Math.floor(canvas.width / fontSize);
    let drops = Array(cols).fill(1);
    
    function draw() {
        ctx.fillStyle = 'rgba(0, 0, 0, 0.05)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = '#00ff41';
        ctx.font = fontSize + 'px "Share Tech Mono", monospace';
        
        cols = Math.floor(canvas.width / fontSize);
        if (drops.length < cols) drops = drops.concat(Array(cols - drops.length).fill(1));
        
        for (let i = 0; i < cols; i++) {
            const ch = chars[Math.floor(Math.random() * chars.length)];
            ctx.fillStyle = i % 5 === 0 ? '#ffffff' : '#00ff41';
            ctx.globalAlpha = Math.random() * 0.5 + 0.3;
            ctx.fillText(ch, i * fontSize, drops[i] * fontSize);
            ctx.globalAlpha = 1;
            if (drops[i] * fontSize > canvas.height && Math.random() > 0.975) drops[i] = 0;
            drops[i]++;
        }
    }
    
    setInterval(draw, 45);
})();
</script>
"""

# ── Inject styles + canvas ───────────────────────────────────────
def get_theme_style(theme_name):
    theme = THEMES[theme_name]
    style = MATRIX_STYLE_BASE
    style = style.replace("#00ff41", theme["P"]).replace("#00cc33", theme["S"])
    style = style.replace("#00140a", theme["UBG"]).replace("#000d05", theme["BBG"])
    style = style.replace("#b3ffcc", theme["T"]).replace("#ff4d00", theme["A"])
    style = style.replace("#ffb380", theme["AT"]).replace("#030f03", theme["CBG"])
    style = style.replace("background-color: #000000 !important;", f"background-color: {theme['BG']} !important;")
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
if "query_count" not in st.session_state:
    st.session_state.query_count = 0
if "news_count" not in st.session_state:
    st.session_state.news_count = 0
if "top_k" not in st.session_state:
    st.session_state.top_k = TOP_K
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
            backgroundColor: 'rgba(0,0,0,0.3)', transition: 'opacity 1s ease-out'
        }});
        window.parent.document.body.appendChild(overlay);

        function createParticle(content, cssProps, keyframes, duration) {{
            const p = window.parent.document.createElement("div");
            p.innerHTML = content;
            Object.assign(p.style, {{ position: 'absolute', fontSize: '4rem', ...cssProps }});
            overlay.appendChild(p);
            p.animate(keyframes, {{ duration: duration, easing: 'ease-out', fill: 'forwards' }});
        }}

        // Only Matrix animation remains
        const chars = '01アイウエオカキクケコサシスセソタチツテトナニヌネノABCDEF';
        const numColumns = 50;
        for(let i=0; i<numColumns; i++) {{
            let colStr = '';
            const length = 30 + Math.floor(Math.random() * 30);
            for(let j=0; j<length; j++) {{
                colStr += chars[Math.floor(Math.random() * chars.length)] + '<br>';
            }}
            
            const isFalling = (i % 2 === 0);
            const startY = isFalling ? '-100vh' : '110vh';
            const endY = isFalling ? '200vh' : '-200vh'; 
            
            createParticle(colStr, {{ 
                left: (i * (100 / numColumns)) + '%', 
                top: startY, 
                color: '#00ff41', 
                fontFamily: '"Share Tech Mono", monospace', 
                fontSize: '1.2rem', 
                lineHeight: '1.0',
                textAlign: 'center',
                textShadow: '0 0 5px #00ff41, 0 0 10px #00cc33',
                opacity: 0.6 + Math.random()*0.4
            }}, [
                {{ transform: 'translateY(0)' }},
                {{ transform: `translateY(${{endY}})` }}
            ], 5000);
        }}

        setTimeout(() => {{
            overlay.style.opacity = '0';
            setTimeout(() => overlay.remove(), 1000);
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


def stream_text(text: str, placeholder, delay: float = 0.008):
    """Simulate streaming/typewriter effect for bot responses."""
    displayed = ""
    for char in text:
        displayed += char
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
    st.markdown('<div class="sidebar-title">// SYSTEM PANEL</div>', unsafe_allow_html=True)
    st.markdown("---")

    # Status indicator
    if st.session_state.pipeline_ready:
        st.markdown(
            '<span class="status-dot"></span><small style="color:#00ff41">SYSTEM ONLINE</small>',
            unsafe_allow_html=True
        )
    else:
        st.markdown(
            '<span style="color:#ff4d00">● INITIALIZING...</span>',
            unsafe_allow_html=True
        )

    st.markdown("---")

    # Stats
    col1, col2 = st.columns(2)
    with col1:
        st.metric("Queries", st.session_state.query_count)
    with col2:
        st.metric("News Intel", st.session_state.news_count)

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
    st.markdown(
        '<div style="font-size:0.65rem; color:#00ff4155; text-align:center; letter-spacing:2px;">'
        'CYBERFRIEND v1.0<br>RAG + GEMINI + NEWSAPI<br>'
        '// STAY SECURE //'
        '</div>',
        unsafe_allow_html=True
    )


# ════════════════════════════════════════════════════════════════
#  HEADER
# ════════════════════════════════════════════════════════════════
st.markdown("""
<div class="cyber-header">
    <h1>🛡 CYBERFRIEND AI</h1>
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
tab1, tab2, tab3 = st.tabs(["💬 Chat & Intel", "🔍 System Analysis", "🏗️ System Architecture"])

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

with tab3:
    st.markdown('<div class="sidebar-title">// ARCHITECTURE & SPECIFICATIONS</div>', unsafe_allow_html=True)
    st.markdown("""
    ```mermaid
    graph TD;
        User((Operator)) -->|Input Query| UI[Streamlit UI Interface]
        UI --> Router{Query Router Engine}
        Router -->|News Request| API[Live News API]
        Router -->|Knowledge Query| RAG[FAISS Local Vector DB]
        Router -->|System Scan| OS[System Analysis Engine]
        API --> LLM[(Groq LLaMA Cloud Core)]
        RAG -->|Contextual Data Object| LLM
        OS --> LLM
        LLM -->|Cyber Intelligence Payload| UI
    ```
    """)
    st.markdown("""
    <div class="msg-bot" style="border-left-color:#00ff41; margin-top:20px;">
    <b>⚙️ Technical Specifications:</b><br><br>
    • <b>Frontend Core:</b> Streamlit running isolated custom Python logic with real-time DOM injection (Canvas Overlays).<br>
    • <b>LLM Inference Engine:</b> Hosted Groq Cloud architecture executing LLaMA models at rapid speeds, completely minimizing local CPU payload.<br>
    • <b>Vector Retrieval System:</b> FAISS (Facebook AI Similarity Search) utilizing local CPU memory for rapid access while indexing knowledge arrays.<br>
    • <b>Embedding Model:</b> <code>sentence-transformers/all-MiniLM-L6-v2</code> mapped explicitly for lightweight CPU constraint compatibility.<br>
    • <b>Global Threat Feed:</b> Live API pipeline linked to external incident reporters.<br>
    • <b>Scan Module Engine:</b> Prompt-isolation design where the hardware parameters are statically analyzed by LLM without executing risky OS-level diagnostic commands.
    </div>
    """, unsafe_allow_html=True)
