"""
Industrial GenAI Production-Grade RAG Package.
Features Hybrid Search (Dense + BM25), Cross-Encoder Re-Ranking, Semantic Caching, A/B Testing, and Cost Dashboards.
"""

from src.rag.hybrid_retriever import HybridRetriever, DocumentChunk, RetrievalResult
from src.rag.rag_service import IndustrialRAGService, RAGResponse
from src.rag.ab_testing import ABTestingHarness, ExperimentVariant, ABTestResult
from src.rag.cost_dashboard import RAGCostAuditor, TokenUsageStats

__all__ = [
    "HybridRetriever",
    "DocumentChunk",
    "RetrievalResult",
    "IndustrialRAGService",
    "RAGResponse",
    "ABTestingHarness",
    "ExperimentVariant",
    "ABTestResult",
    "RAGCostAuditor",
    "TokenUsageStats",
]
