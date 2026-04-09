"""
assistant.py – Core AI assistant logic.
Handles routing between RAG knowledge base and real-time news.
Formats responses for cybersecurity scenarios and general queries.
"""

import os
from langchain_groq import ChatGroq
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnablePassthrough, RunnableLambda

from news_module import fetch_cybersecurity_news, format_articles_for_llm
from config import GROQ_API_KEY, LLM_MODEL, LLM_TEMPERATURE, TOP_K, NEWS_TRIGGER_WORDS

# ─────────────────────────────────────────────────────
# PROMPT TEMPLATES
# ─────────────────────────────────────────────────────

RAG_PROMPT = ChatPromptTemplate.from_template("""You are a friendly and knowledgeable cybersecurity expert assistant.
Use ONLY the following context from the knowledge base to answer the user's question.

Context:
{context}

User Question: {question}

Instructions:
- If the user is DESCRIBING A SCENARIO (e.g., "I clicked a link", "I got a weird email", "my computer is acting strange"):
  Respond in EXACTLY this format:

  Attack Type: [identify the most likely attack]
  Explanation: [explain it clearly in simple language]
  What to Do: [give 3–5 concrete steps the user should take]
  Confidence: [High / Medium / Low – based on context match] (L2 Distance: [Include the L2 Distance of the most relevant chunk used])

- If it is a GENERAL CYBERSECURITY QUESTION (e.g., "What is phishing?", "How does ransomware work?"):
  Give a clear, educational answer.

- If the answer is NOT in the context, respond with:
  "I don't have enough information on this in my knowledge base. Please consult a security professional."

IMPORTANT: Never guess or make up facts. Be honest when unsure.
""")

NEWS_PROMPT = ChatPromptTemplate.from_template("""You are a cybersecurity news analyst.
Summarize the following recent cybersecurity news articles in a clear, non-technical way.

News Articles:
{news_content}

For EACH article, respond in EXACTLY this format:

Recent Cyber Incident: [article headline]
Summary: [2–3 sentence plain-English summary]
Impact: [who is affected and what the consequences might be]

---

Keep summaries factual and avoid speculation.
""")

SYSTEM_ANALYSIS_PROMPT = ChatPromptTemplate.from_template("""You are a cybersecurity system analyzer.
Based on the following user-provided system details, perform a security analysis. Do NOT attempt to run any actual system commands. Assure the user that the analysis is based solely on their input for their privacy.

User System Details:
- Operating System: {os}
- Browser: {browser}
- Antivirus Status: {av}
- Recent Suspicious Activity: {activity}

Provide your analysis in EXACTLY this format:

### 1. Potential Vulnerabilities
[List 2-3 potential risks based on their OS, browser, or AV status]

### 2. Activity Assessment
[Analyze the "Recent Suspicious Activity". Is it a known threat? Explain it.]

### 3. Recommended Actions
[List 3-4 concrete steps they should take immediately to improve security]
""")


# ─────────────────────────────────────────────────────
# ASSISTANT CLASS
# ─────────────────────────────────────────────────────

class CybersecurityAssistant:
    """
    Main assistant that routes queries to:
    1. RAG pipeline (knowledge base) for cybersecurity questions
    2. NewsAPI (real-time) for news/recent incidents
    """

    def __init__(self, retriever):
        self.retriever = retriever
        self.llm = ChatGroq(
            model=LLM_MODEL,
            temperature=LLM_TEMPERATURE,
            groq_api_key=GROQ_API_KEY
        )
        self.output_parser = StrOutputParser()
        self._build_rag_chain()

    # ──────────────────────────────────────
    # RAG Chain
    # ──────────────────────────────────────
    def _build_rag_chain(self):
        """Build the LangChain RAG chain."""

        def retrieve_context(query: str) -> str:
            """Retrieve relevant docs and join them into a single context string with L2 distance."""
            vectorstore = self.retriever.vectorstore
            k = self.retriever.search_kwargs.get("k", 4)
            docs_and_scores = vectorstore.similarity_search_with_score(query, k=k)
            
            if not docs_and_scores:
                return "No relevant information found in knowledge base."
            
            context_parts = []
            for doc, score in docs_and_scores:
                context_parts.append(f"[L2 Distance: {score:.4f}]\n{doc.page_content}")
                
            return "\n\n".join(context_parts)

        self.rag_chain = (
            {
                "context": RunnableLambda(retrieve_context),
                "question": RunnablePassthrough()
            }
            | RAG_PROMPT
            | self.llm
            | self.output_parser
        )

    # ──────────────────────────────────────
    # Routing
    # ──────────────────────────────────────
    def is_news_query(self, query: str) -> bool:
        """Detect if the user is asking for real-time/recent news."""
        query_lower = query.lower()
        return any(word in query_lower for word in NEWS_TRIGGER_WORDS)

    # ──────────────────────────────────────
    # News Response
    # ──────────────────────────────────────
    def get_news_response(self) -> str:
        """Fetch and summarize latest cybersecurity news using LLM."""
        print("  [*] Contacting NewsAPI...")
        articles, error = fetch_cybersecurity_news()

        if error:
            return f"[!] News Error: {error}"

        if not articles:
            return "[!] No recent cybersecurity news articles were found."

        print(f"  [+] Found {len(articles)} articles. Summarizing...")
        news_content = format_articles_for_llm(articles)

        news_chain = NEWS_PROMPT | self.llm | self.output_parser
        return news_chain.invoke({"news_content": news_content})

    # ──────────────────────────────────────
    # RAG Response
    # ──────────────────────────────────────
    def get_rag_response(self, query: str) -> str:
        """Answer a query using the RAG knowledge base."""
        print("  [*] Searching knowledge base...")
        try:
            return self.rag_chain.invoke(query)
        except Exception as e:
            return f"[!] Error generating response: {str(e)}"

    # ──────────────────────────────────────
    # Base LLM Response (No RAG)
    # ──────────────────────────────────────
    def get_llm_response(self, query: str) -> str:
        """Answer a query directly using the LLM without knowledge base context."""
        print("  [*] Answering directly via LLM...")
        try:
            general_prompt = ChatPromptTemplate.from_template(
                "You are a friendly and knowledgeable cybersecurity expert assistant. "
                "Answer the user's question clearly and accurately.\n\nUser Question: {question}"
            )
            chain = general_prompt | self.llm | self.output_parser
            return chain.invoke({"question": query})
        except Exception as e:
            return f"[!] Error generating response: {str(e)}"

    # ──────────────────────────────────────
    # System Analysis Response
    # ──────────────────────────────────────
    def analyze_system(self, os_val: str, browser_val: str, av_val: str, activity_val: str) -> str:
        """Analyze user system inputs for vulnerabilities."""
        print("  [*] Analyzing user system inputs...")
        try:
            chain = SYSTEM_ANALYSIS_PROMPT | self.llm | self.output_parser
            return chain.invoke({
                "os": os_val,
                "browser": browser_val,
                "av": av_val,
                "activity": activity_val
            })
        except Exception as e:
            return f"[!] Error during system analysis: {str(e)}"

    # ──────────────────────────────────────
    # Main Entry Point
    # ──────────────────────────────────────
    def respond(self, query: str, use_rag: bool = True) -> str:
        """
        Route query to appropriate handler:
        - News keywords → NewsAPI + LLM summary
        - Everything else → RAG pipeline or direct LLM
        """
        query = query.strip()
        if not query:
            return "Please type a question."

        if self.is_news_query(query):
            return self.get_news_response()
        else:
            if use_rag:
                return self.get_rag_response(query)
            else:
                return self.get_llm_response(query)

