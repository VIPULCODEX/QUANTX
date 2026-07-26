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
from config import (
    NEWS_TRIGGER_WORDS, LLM_MAX_TOKENS, LLM_MODEL, LLM_TEMPERATURE, GROQ_API_KEY_LIST
)
from security import validate_query

# ─────────────────────────────────────────────────────
# PROMPT TEMPLATES
# ─────────────────────────────────────────────────────

RAG_PROMPT = ChatPromptTemplate.from_template("""You are QuantX, an advanced AI assistant specializing in cybersecurity.
Use the following context from your knowledge base to answer the user's question.

Context:
{context}

User Question: {question}

Instructions:
- If the context contains relevant information, use it to provide a structured and detailed response.
- If the user is DESCRIBING A SCENARIO:
  Respond in EXACTLY this format:
  Attack Type: [identify the most likely attack]
  Explanation: [explain it clearly in simple language]
  What to Do:
  - [step 1]
  - [step 2]
  - [step 3]
  Confidence: [High / Medium / Low] (L2 Distance: [Include score])

- If it is a GENERAL TECHNICAL QUESTION:
  Respond in EXACTLY this format:
  Answer: [2-5 concise lines]
  Key Points:
  - [point 1]
  - [point 2]
  - [point 3]

- If the answer is NOT in the context, respond EXACTLY with:
  "I don't have enough specific information on this in my local knowledge matrix. Initializing general reasoning fallback..."

IMPORTANT:
- Keep responses professional and concise.
- Use only the provided context if possible.
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

    def __init__(self, retriever, max_tokens=300):
        import itertools
        self.retriever = retriever
        
        self.llm_pool = []
        for key in GROQ_API_KEY_LIST:
            self.llm_pool.append(ChatGroq(
                model=LLM_MODEL,
                temperature=LLM_TEMPERATURE,
                groq_api_key=key,
                max_tokens=max_tokens or LLM_MAX_TOKENS
            ))
            
        if not self.llm_pool:
            raise ValueError("No GROQ API keys found in the environment.")
            
        # Infinite round-robin iterator for load balancing
        self.llm_cycler = itertools.cycle(self.llm_pool)
        
        # Keep a default reference for any standard Langchain tools that need a single LLM
        self.llm = self.llm_pool[0]
        
        self.output_parser = StrOutputParser()
        self._build_rag_chain()

    # ──────────────────────────────────────
    # RAG Chain
    # ──────────────────────────────────────
    def _build_rag_chain(self):
        """Build the LangChain RAG chain."""

        def retrieve_context(query: str) -> str:
            """Retrieve relevant docs and join into one context string with score hints."""
            # Dynamic K selection based on query complexity
            word_count = len(query.split())
            if word_count > 15 or any(w in query.lower() for w in ["explain", "detail", "compare", "full"]):
                k = 5  # Complex queries need more context
            elif word_count < 4:
                k = 2  # Simple short questions need precise context
            else:
                k = 3  # Default optimal

            if hasattr(self.retriever, "similarity_search_with_score"):
                docs_and_scores = self.retriever.similarity_search_with_score(query, k=k)
            elif hasattr(self.retriever, "vectorstore"):
                docs_and_scores = self.retriever.vectorstore.similarity_search_with_score(query, k=k)
            else:
                docs = self.retriever.get_relevant_documents(query)
                docs_and_scores = [(d, 0.0) for d in docs[:k]]
            
            if not docs_and_scores:
                return "No relevant information found in knowledge base."
            
            context_parts = []
            for doc, score in docs_and_scores:
                tier = doc.metadata.get("tier", "static") if doc.metadata else "static"
                context_parts.append(
                    f"[Tier: {tier} | L2 Distance: {score:.4f}]\n{doc.page_content}"
                )
                
            return "\n\n".join(context_parts)

        self.rag_chain = (
            {
                "context": RunnableLambda(retrieve_context),
                "question": RunnablePassthrough()
            }
            | RAG_PROMPT
            | RunnableLambda(lambda x: next(self.llm_cycler).invoke(x))
            | self.output_parser
        )

    # ──────────────────────────────────────
    # Routing
    # ──────────────────────────────────────
    def is_news_query(self, query: str) -> bool:
        """Detect if the user is asking for real-time/recent news."""
        query_lower = query.lower()
        return any(word in query_lower for word in NEWS_TRIGGER_WORDS)

    def is_general_chatter(self, query: str) -> bool:
        """Detect greeting or generic conversation."""
        query_lower = query.lower().strip()
        chatter_keywords = ["hi", "hello", "hey", "how are you", "who are you", "what are you", "thanks", "thank you", "bye"]
        if len(query_lower.split()) <= 4 and any(query_lower.startswith(w) or query_lower == w for w in chatter_keywords):
            return True
        return False

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

        news_chain = NEWS_PROMPT | RunnableLambda(lambda x: next(self.llm_cycler).invoke(x)) | self.output_parser
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
                "You are QuantX, a highly capable AI assistant. "
                "While you specialize in cybersecurity and threat intelligence, you are fully equipped to handle any general query or task. "
                "Provide a helpful, accurate, and professional response to the user's request.\n\n"
                "User Request: {question}\n\n"
                "Response:"
            )
            chain = general_prompt | RunnableLambda(lambda x: next(self.llm_cycler).invoke(x)) | self.output_parser
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
            chain = SYSTEM_ANALYSIS_PROMPT | RunnableLambda(lambda x: next(self.llm_cycler).invoke(x)) | self.output_parser
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
        - General chatter → direct LLM (bypassing RAG)
        - Everything else → RAG pipeline or direct LLM
        """
        try:
            query = validate_query(query)
        except ValueError as e:
            return f"[SECURITY ALERT] {str(e)}"

        if not query:
            return "Connection established. Please provide input."

        if self.is_news_query(query):
            return self.get_news_response()
            
        if self.is_general_chatter(query):
            print("  [*] Auto-detected general chatter. Bypassing RAG.")
            use_rag = False

        if use_rag:
            rag_res = self.get_rag_response(query)
            # Automatic fallback if RAG didn't find specific info
            if "Initializing general reasoning fallback" in rag_res:
                print("  [*] RAG context insufficient. Falling back to direct LLM.")
                return self.get_llm_response(query)
            return rag_res
        else:
            return self.get_llm_response(query)

