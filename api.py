from fastapi import FastAPI
from pydantic import BaseModel
import time
from rag_pipeline import RAGPipeline
from assistant import CybersecurityAssistant
from config import TOP_K

app = FastAPI(title="Cyberfriend AI API")

# Initialize pipeline once on startup
print("Initializing RAG Pipeline...")
rag = RAGPipeline()
rag.initialize()
retriever = rag.get_retriever(k=TOP_K)
assistant = CybersecurityAssistant(retriever)
print("Pipeline Ready.")

class ChatRequest(BaseModel):
    query: str

class ChatResponse(BaseModel):
    response: str
    time_taken: float

@app.post("/api/chat", response_model=ChatResponse)
def handle_chat(request: ChatRequest):
    start_time = time.time()
    
    # Process the query using the assistant
    # This runs synchronously in a FastAPI thread pool worker
    result = assistant.respond(request.query)
    
    time_taken = time.time() - start_time
    return ChatResponse(response=result, time_taken=round(time_taken, 2))

@app.get("/api/health")
def health_check():
    return {"status": "online"}
