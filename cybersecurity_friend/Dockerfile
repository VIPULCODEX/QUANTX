# Use official Python lightweight image
FROM python:3.10-slim

# Install system dependencies (needed for FAISS and other libs)
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Hugging Face Spaces run safely under a non-root user. Let's set it up:
RUN useradd -m -u 1000 user
USER user

# Set up environment variables for the user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH \
    # Cache HuggingFace models inside the container (avoids re-downloading on each request)
    HF_HOME=/home/user/.cache/huggingface \
    TRANSFORMERS_CACHE=/home/user/.cache/huggingface \
    SENTENCE_TRANSFORMERS_HOME=/home/user/.cache/sentence_transformers

# Set the working directory
WORKDIR $HOME/app

# Copy requirements and install them
COPY --chown=user:user requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Pre-download the embedding model at BUILD TIME so startup is instant
# (This bakes the model into the Docker image — no cold-start delay)
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')"

# Copy the rest of the application
COPY --chown=user:user . .

# Expose the default Hugging Face Port
EXPOSE 7860
ENV PORT=7860

# ── FIXED: 1 worker (not 2) prevents OOM on HF free tier ──────────────────
# --workers 1      : Only 1 process. 2 workers × embedding model = OOM kill.
# --timeout 300    : Give the RAG pipeline + FAISS index 5 min to load.
# --preload        : Load the app in master, fork workers (saves RAM).
# --keep-alive 5   : Keep connections alive between requests.
CMD ["gunicorn", "api:app", \
     "--workers", "1", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:7860", \
     "--timeout", "300", \
     "--preload", \
     "--keep-alive", "5"]
