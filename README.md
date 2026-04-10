# 🛡️ QuantX – AI Assistant

A Python-based AI assistant that explains cybersecurity concepts, identifies attack types from real user scenarios, suggests preventive actions, and fetches real-time cybersecurity news — all powered by RAG + Gemini + HuggingFace.

---

## 📁 Project Structure

```text
cybersecurity_friend/
│
├── app.py                ← Streamlit UI Entry Point (Matrix-style Web Interface)
├── main.py               ← CLI Entry point
├── config.py             ← All settings and environment variables
├── rag_pipeline.py       ← Document loading, chunking, FAISS indexing
├── assistant.py          ← Core AI logic (routing, prompts, responses)
├── news_module.py        ← Real-time news via NewsAPI
├── k_analysis.py         ← K factor analysis for RAG performance
│
├── data/                 ← 📂 PUT YOUR KNOWLEDGE BASE DOCUMENTS HERE
│   └── cybersecurity_kb.txt   ← Built-in sample knowledge base
│
├── faiss_index/          ← Auto-created index directory
│   └── index.faiss       ← Saved FAISS vector index
│
├── requirements.txt      ← Python dependencies
├── .env.example          ← Template for your API keys
├── k_analysis_results.json ← Analysis results data
└── README.md             ← This file
```

---

## 📸 Screenshots

*(Replace these placeholders with actual screenshots of your application)*

**Streamlit Web Interface (Matrix-style Theme)**
![Streamlit App Screenshot](https://via.placeholder.com/800x400.png?text=Streamlit+Matrix+UI)

**Command Line Interface**
![CLI Interface Screenshot](https://via.placeholder.com/800x200.png?text=CLI+Interaction)

---

## 🚀 Quick Start (Step-by-Step)

### Step 1: Install Dependencies
```bash
pip install -r requirements.txt
```

### Step 2: Set Up API Keys
Copy the example env file and add your keys:
```bash
# Windows
copy .env.example .env

# Mac/Linux
cp .env.example .env
```

Then edit `.env` with a text editor:
```
GOOGLE_API_KEY=your_gemini_key_here
NEWS_API_KEY=your_newsapi_key_here
```

### Step 3: Run the Assistant

You can run the assistant in two ways:

**Option A: Web Interface (Recommended)**
Provides a Matrix-style web UI with a sidebar and interactive chat.
```bash
streamlit run app.py
```

**Option B: Command Line Interface (CLI)**
Runs entirely in your terminal.
```bash
python main.py
```

That's it! The assistant will:
1. Load the built-in knowledge base from `data/`
2. Build a FAISS index (first run only — takes ~30 seconds)
3. Launch the chosen interface

---

## 🔑 API Keys You Need

| Key | Required? | Where to Get | Cost |
|-----|-----------|-------------|------|
| `GOOGLE_API_KEY` | ✅ Yes | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | Free |
| `NEWS_API_KEY` | ⚠️ Optional | [newsapi.org](https://newsapi.org/) | Free (100 req/day) |

> Without `NEWS_API_KEY`, the assistant still works — just without real-time news.

---

## 📚 Knowledge Base (Required Documents)

The `data/` folder comes with a built-in knowledge base (`cybersecurity_kb.txt`) that covers:

| Topic | Covered |
|-------|---------|
| Phishing | ✅ |
| Ransomware | ✅ |
| Man-in-the-Middle | ✅ |
| SQL Injection | ✅ |
| DDoS Attacks | ✅ |
| Social Engineering | ✅ |
| Malware | ✅ |
| Password Attacks | ✅ |
| Zero-Day Exploits | ✅ |
| Insider Threats | ✅ |
| Best Practices | ✅ |
| Incident Response | ✅ |
| Network Security | ✅ |
| Data Privacy | ✅ |
| Safe Browsing | ✅ |

### Adding More Documents (Optional)
To expand the knowledge base, simply add `.pdf` or `.txt` files to the `data/` folder and then run `rebuild` inside the assistant or restart the program.

**Recommended FREE Resources:**
- OWASP Top 10: https://owasp.org/Top10/
- NIST Cybersecurity Framework: https://www.nist.gov/cyberframework
- CISA Resources: https://www.cisa.gov/resources-tools
- Any cybersecurity textbook PDFs or class notes

---

## 💬 Example Queries

### General Questions
```
You: What is phishing?
You: How does ransomware work?
You: What is a man-in-the-middle attack?
You: Explain SQL injection in simple terms
```

### Scenario-Based (Gets: Attack Type + Explanation + Actions)
```
You: I clicked on a suspicious link in an email, what should I do?
You: My computer is running very slowly and I see unknown processes
You: I got an email saying I won a prize and need to login to claim it
You: Someone called me saying they are from IT and need my password
You: I found a USB stick in the parking lot and plugged it into my computer
```

### Real-Time News
```
You: What happened recently in cybersecurity?
You: Show me the latest cyber incidents
You: Any recent data breach news today?
```

### CLI Commands
```
You: help      → Show example queries
You: rebuild   → Rebuild FAISS index from updated documents
You: exit      → Quit the assistant
```

---

## 📤 Example Output

### General Query
```
You: What is phishing?

🛡️  Assistant Response:
══════════════════════════════════════════════
Phishing is a type of social engineering attack where cybercriminals send 
fraudulent messages — usually emails — designed to trick recipients into 
revealing sensitive information such as passwords, credit card numbers, or 
personal data...
══════════════════════════════════════════════
```

### Scenario Query
```
You: I clicked on a suspicious link in an email, what should I do?

🛡️  Assistant Response:
══════════════════════════════════════════════
Attack Type: Phishing Attack

Explanation: You may have clicked a phishing link designed to steal your 
credentials or install malware on your device. Phishing links often lead to 
fake login pages or trigger silent malware downloads.

What to Do:
1. Disconnect from the internet immediately
2. Run a full antivirus scan
3. Change all passwords from a different, clean device
4. Enable MFA on all important accounts
5. Monitor bank/card statements for unusual activity

Confidence: High
══════════════════════════════════════════════
```

### News Query
```
You: What happened recently in cybersecurity?

🛡️  Assistant Response:
══════════════════════════════════════════════
Recent Cyber Incident: Major Bank Data Breach Exposes 2M Records
Summary: A major financial institution suffered a breach exposing 2 million 
customer records including names, email addresses, and account numbers...
Impact: Customers at risk of identity theft and phishing follow-up attacks.

---

Recent Cyber Incident: Ransomware Hits Healthcare System...
══════════════════════════════════════════════
```

---

## ⚙️ Customization

Edit `config.py` to adjust settings:

```python
CHUNK_SIZE    = 500    # Increase for longer context per chunk
CHUNK_OVERLAP = 100    # Higher = more continuity between chunks
TOP_K         = 3      # How many chunks to retrieve per query
LLM_MODEL     = "gemini-1.5-flash"  # Or "gemini-pro"
```

---

## 🔧 Troubleshooting

| Problem | Solution |
|---------|---------|
| `GOOGLE_API_KEY not set` | Add your key to `.env` file |
| `Resource Exhausted` error | Wait — you hit the daily quota. Try tomorrow or use another key |
| `API key expired` | Regenerate key at aistudio.google.com/apikey |
| `No documents loaded` | Ensure files exist in `data/` folder |
| Slow first run | Normal — embedding model downloads on first run (~200MB) |
| News not working | Check NEWS_API_KEY in `.env` |
| Index is outdated | Type `rebuild` inside the assistant |

---

## 🧠 Architecture

```
User Query
    │
    ▼
Routing Logic
    │
    ├── [ News keywords? ] ──► NewsAPI → LLM Summarizer → Response
    │
    └── [ Other query? ] ──► Retriever → FAISS → Relevant Chunks
                                                       │
                                                 Gemini LLM
                                                       │
                                           Formatted Response
```

---

## 📋 Tech Stack

| Component | Technology |
|-----------|-----------|
| LLM | Google Gemini 1.5 Flash |
| Embeddings | HuggingFace all-MiniLM-L6-v2 |
| Vector Store | FAISS (CPU) |
| Framework | LangChain |
| News | NewsAPI |
| Interface | Python CLI |
