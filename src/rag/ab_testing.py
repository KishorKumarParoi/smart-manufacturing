"""
Production A/B Testing Harness for Industrial RAG Services.
Evaluates competing model pipelines (e.g., Dense-Only vs Hybrid-Reranked) across latency, cost, and quality.
Provides statistical comparison and automated canary promotion gates.
"""

import random
import time
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field


@dataclass
class ExperimentVariant:
    variant_id: str  # "A" or "B"
    name: str
    description: str
    traffic_weight: float  # e.g., 0.5 for 50/50 split
    total_requests: int = 0
    total_latency_ms: float = 0.0
    latencies: List[float] = field(default_factory=list)
    total_tokens: int = 0
    positive_ratings: int = 0
    negative_ratings: int = 0
    geval_scores: List[float] = field(default_factory=list)


@dataclass
class ABTestResult:
    variant: str
    latency_ms: float
    geval_score: float
    user_rating: Optional[int] = None


class ABTestingHarness:
    """
    Manages RAG A/B experimentation, traffic routing, metric aggregation, and winner evaluation.
    """

    def __init__(self):
        self.variants: Dict[str, ExperimentVariant] = {
            "A": ExperimentVariant(
                variant_id="A",
                name="Dense-Baseline",
                description="Standard Dense Cosine Vector Search without Cross-Encoder",
                traffic_weight=0.5
            ),
            "B": ExperimentVariant(
                variant_id="B",
                name="Hybrid-Reranked-Challenger",
                description="Hybrid Dense+BM25 with Reciprocal Rank Fusion & Cross-Encoder Reranking",
                traffic_weight=0.5
            )
        }
        self.test_history: List[ABTestResult] = []

    def route_request(self) -> str:
        """
        Routes incoming query to variant based on configured traffic weights.
        """
        r = random.random()
        cumulative = 0.0
        for vid, variant in self.variants.items():
            cumulative += variant.traffic_weight
            if r <= cumulative:
                return vid
        return "A"

    def record_interaction(
        self,
        variant_id: str,
        latency_ms: float,
        tokens_used: int,
        geval_score: float,
        user_rating: Optional[int] = None
    ):
        """
        Records operational telemetry from an A/B interaction.
        """
        if variant_id not in self.variants:
            return

        v = self.variants[variant_id]
        v.total_requests += 1
        v.total_latency_ms += latency_ms
        v.latencies.append(latency_ms)
        v.total_tokens += tokens_used
        v.geval_scores.append(geval_score)

        if user_rating == 1:
            v.positive_ratings += 1
        elif user_rating == -1:
            v.negative_ratings += 1

        self.test_history.append(ABTestResult(
            variant=variant_id,
            latency_ms=latency_ms,
            geval_score=geval_score,
            user_rating=user_rating
        ))

    def get_experiment_analytics(self) -> Dict[str, Any]:
        """
        Calculates comparative performance metrics across variants.
        """
        analytics = {}
        for vid, v in self.variants.items():
            reqs = max(1, v.total_requests)
            sorted_lat = sorted(v.latencies) if v.latencies else [0.0]
            p50 = sorted_lat[int(len(sorted_lat) * 0.50)]
            p95 = sorted_lat[min(len(sorted_lat) - 1, int(len(sorted_lat) * 0.95))]
            avg_geval = sum(v.geval_scores) / max(1, len(v.geval_scores))
            total_feedback = v.positive_ratings + v.negative_ratings
            satisfaction = (v.positive_ratings / max(1, total_feedback)) * 100 if total_feedback > 0 else 100.0

            analytics[vid] = {
                "name": v.name,
                "total_requests": v.total_requests,
                "p50_latency_ms": round(p50, 2),
                "p95_latency_ms": round(p95, 2),
                "avg_geval_score": round(avg_geval, 3),
                "satisfaction_rate_pct": round(satisfaction, 1),
                "total_tokens": v.total_tokens,
                "estimated_cost_usd": round(v.total_tokens * 0.000002, 4)  # $2 per million tokens
            }

        # Compare quality uplift
        a_score = analytics.get("A", {}).get("avg_geval_score", 0.0)
        b_score = analytics.get("B", {}).get("avg_geval_score", 0.0)
        uplift_pct = round(((b_score - a_score) / max(0.001, a_score)) * 100, 2)

        return {
            "variants": analytics,
            "quality_uplift_b_vs_a_pct": uplift_pct,
            "recommended_action": "PROMOTE_VARIANT_B" if (uplift_pct > 5.0 and analytics.get("B", {}).get("p95_latency_ms", 999) < 200) else "CONTINUE_TESTING"
        }
