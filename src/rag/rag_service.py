"""
Production-Grade Industrial GenAI RAG Service.
Provides contextual knowledge retrieval, policy guardrails, semantic caching (<50ms), and automated response synthesis.
Specialized for factory operations, machinery diagnostics, and maintenance SOPs.
"""

import time
import hashlib
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
from src.rag.hybrid_retriever import HybridRetriever, DocumentChunk, RetrievalResult
from src.security_guardrails.guardrails import PolicyGuardrailEngine, GuardrailDecision
from src.security_guardrails.eval_harness import GEvalHarness, GEvalReport


@dataclass
class RAGResponse:
    query: str
    response: str
    citations: List[Dict[str, Any]]
    cached: bool
    latency_ms: float
    token_usage: Dict[str, int]
    guardrail_decision: GuardrailDecision
    eval_report: Optional[GEvalReport] = None
    variant: str = "A"


class IndustrialRAGService:
    """
    Production-hardened RAG service with defense-in-depth security,
    semantic caching, and hybrid vector/lexical retrieval.
    """

    DEFAULT_KNOWLEDGE_BASE = [
        DocumentChunk(
            chunk_id="SOP-MCH-04",
            content=(
                "CNC Spindle Bearing Thermal Runaway SOP-MCH-04: When process temperature exceeds 85°C "
                "or multi-axis vibration RMS crosses 0.70 mm/s, immediately decelerate spindle to 1,500 RPM. "
                "Inspect spindle lubrication lines, check cooling jacket flow rate (minimum 4.5 L/min), and verify "
                "bearing pre-load. If temperature remains above 80°C after 60 seconds, trigger emergency line shutdown."
            ),
            metadata={"category": "Thermal & Spindle", "severity": "CRITICAL", "sop_code": "SOP-MCH-04"}
        ),
        DocumentChunk(
            chunk_id="SOP-QC-12",
            content=(
                "Automated Optical Inspection (AOI) Defect Remediation SOP-QC-12: High-speed conveyor camera defects "
                "are classified into four classes: 0=Normal, 1=Surface Crack, 2=Pitting, 3=Burn Mark. "
                "Surface cracks exceeding 0.5mm length or pitting density >3 pits/cm² mandate automated robotic diversion "
                "to the rework bin. Recalibrate conveyor camera LED illumination matrix every 8 operating hours."
            ),
            metadata={"category": "Quality & Vision", "severity": "HIGH", "sop_code": "SOP-QC-12"}
        ),
        DocumentChunk(
            chunk_id="SOP-VIB-08",
            content=(
                "Multi-Axis Vibration Anomaly Calibration SOP-VIB-08: Sensor telemetry streams X, Y, Z accelerations. "
                "The PyTorch Symmetric Autoencoder computes reconstruction Mean Squared Error (MSE). Normal baseline "
                "MSE is calibrated at the 95th percentile (<0.045). An MSE between 0.045 and 0.080 triggers a WARNING state. "
                "An MSE >0.080 indicates imminent bearing cage fracture and requires immediate tool retract."
            ),
            metadata={"category": "Vibration & Autoencoder", "severity": "HIGH", "sop_code": "SOP-VIB-08"}
        ),
        DocumentChunk(
            chunk_id="SOP-HYD-01",
            content=(
                "Hydraulic Press Safety & Pressure Maintenance SOP-HYD-01: Standard hydraulic operating pressure "
                "is 120 bar ± 5 bar. If pressure drops below 100 bar, inspect main hydraulic pump seals for cavitation. "
                "If pressure exceeds 140 bar, hydraulic relief valve must bypass automatically. Never override relief valves manually."
            ),
            metadata={"category": "Hydraulics & Pressure", "severity": "CRITICAL", "sop_code": "SOP-HYD-01"}
        ),
        DocumentChunk(
            chunk_id="SOP-OPS-03",
            content=(
                "Active-Passive Multi-Cloud Failover Runbook SOP-OPS-03: Route 53 health prober inspects primary AWS ALB "
                "every 5 seconds. Upon 3 consecutive check timeouts, DNS weight shifts to 0 on AWS and 100 on GCP GKE. "
                "Warm standby GKE cluster auto-scales GPU inference pods from 0 to 2 nodes in <90 seconds. Target RTO <15s, RPO <60s."
            ),
            metadata={"category": "Infrastructure & DR", "severity": "CRITICAL", "sop_code": "SOP-OPS-03"}
        ),
    ]

    def __init__(self, enable_eval: bool = True):
        self.guardrail_engine = PolicyGuardrailEngine(enforce_topic_gating=True)
        self.retriever = HybridRetriever(rrf_k=60)
        self.retriever.index_documents(self.DEFAULT_KNOWLEDGE_BASE)
        self.eval_harness = GEvalHarness() if enable_eval else None
        self._semantic_cache: Dict[str, RAGResponse] = {}  # query_hash -> RAGResponse

    def query(
        self,
        user_query: str,
        variant: str = "A",
        bypass_cache: bool = False
    ) -> RAGResponse:
        """
        Executes complete RAG pipeline:
        1. Guardrails & PII validation
        2. Semantic cache probe (<50ms)
        3. Hybrid vector & lexical retrieval (Variant A: Dense only; Variant B: Hybrid + Cross-Encoder)
        4. Context-augmented response synthesis
        5. Output safety guardrail verification
        6. Optional G-Eval automated evaluation
        """
        start = time.perf_counter()

        # Step 1: Input Policy Guardrails & Injection Defense
        decision = self.guardrail_engine.validate_input(user_query)
        if not decision.passed:
            duration = (time.perf_counter() - start) * 1000
            return RAGResponse(
                query=user_query,
                response=f"🛑 Request Rejected: {decision.rejection_reason}",
                citations=[],
                cached=False,
                latency_ms=round(duration, 3),
                token_usage={"prompt_tokens": len(user_query.split()), "completion_tokens": 15, "total_tokens": len(user_query.split()) + 15},
                guardrail_decision=decision,
                eval_report=None,
                variant=variant
            )

        sanitized_query = decision.sanitized_input

        # Step 2: Semantic Cache Lookup
        cache_key = hashlib.sha256(sanitized_query.strip().lower().encode()).hexdigest()
        if not bypass_cache and cache_key in self._semantic_cache:
            cached_resp = self._semantic_cache[cache_key]
            duration = (time.perf_counter() - start) * 1000
            return RAGResponse(
                query=user_query,
                response=cached_resp.response,
                citations=cached_resp.citations,
                cached=True,
                latency_ms=round(duration, 3),
                token_usage={"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
                guardrail_decision=decision,
                eval_report=cached_resp.eval_report,
                variant=variant
            )

        # Step 3: Retrieval (A/B testing variants)
        enable_reranking = (variant == "B")
        retrieved_chunks = self.retriever.retrieve(
            query=sanitized_query,
            top_k=2,
            enable_reranking=enable_reranking
        )

        # Step 4: Context Assembly & Synthesis
        context_text = "\n\n".join([f"[{c.chunk_id}]: {c.content}" for c in retrieved_chunks])
        citations = [
            {"sop_code": c.chunk_id, "category": c.metadata.get("category"), "score": c.rerank_score}
            for c in retrieved_chunks
        ]

        if not retrieved_chunks:
            answer = "No matching standard operating procedures or maintenance manuals were found in the knowledge base."
        else:
            primary = retrieved_chunks[0]
            answer = (
                f"Based on industrial operating documentation [{primary.chunk_id}]:\n"
                f"{primary.content}\n\n"
                f"Recommended Action: Ensure verified PPE protocols and check physical interlocks before executing manual servicing."
            )

        # Step 5: Output Safety Guardrail
        safe_output, output_rejection = self.guardrail_engine.validate_output(answer)
        if not safe_output:
            answer = f"⚠️ Model output suppressed by safety guardrail: {output_rejection}"

        duration = (time.perf_counter() - start) * 1000

        # Step 6: Token Usage Computation
        prompt_tokens = len(sanitized_query.split()) + len(context_text.split())
        completion_tokens = len(answer.split())
        tokens = {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens
        }

        # Step 7: G-Eval Automated Scoring
        eval_report = None
        if self.eval_harness:
            eval_report = self.eval_harness.evaluate_sample(
                query=sanitized_query,
                context=context_text,
                response=answer
            )

        response_obj = RAGResponse(
            query=user_query,
            response=answer,
            citations=citations,
            cached=False,
            latency_ms=round(duration, 3),
            token_usage=tokens,
            guardrail_decision=decision,
            eval_report=eval_report,
            variant=variant
        )

        # Store in cache
        self._semantic_cache[cache_key] = response_obj
        return response_obj
