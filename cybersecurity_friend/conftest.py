"""Shared pytest setup: stub the heavy ML imports so api.py loads offline."""
import sys
import types

if "rag_pipeline" not in sys.modules:
    _rag = types.ModuleType("rag_pipeline")
    _rag.RAGPipeline = object
    sys.modules["rag_pipeline"] = _rag

# Use the real assistant module when langchain is installed (so wiring can be
# tested); otherwise stub it.
try:
    import assistant  # noqa: F401
except ImportError:
    _a = types.ModuleType("assistant")
    _a.CybersecurityAssistant = object
    sys.modules["assistant"] = _a
