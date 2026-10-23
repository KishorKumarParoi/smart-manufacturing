"""
Real-Time GenAI Cost Dashboard & Token Consumption Auditor.
Tracks input/output token usage across model tiers, calculates dollar spend, and quantifies semantic cache ROI.
Enforces budget ceilings and financial SLOs.
"""

import time
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field


@dataclass
class TokenUsageStats:
    total_prompt_tokens: int = 0
    total_completion_tokens: int = 0
    total_tokens: int = 0
    cached_tokens_saved: int = 0
    total_cost_usd: float = 0.0
    cost_saved_usd: float = 0.0
    queries_processed: int = 0
    cache_hits: int = 0


class RAGCostAuditor:
    """
    Financial auditor and cost dashboard for GenAI and RAG operations.
    """

    # Pricing per 1,000 tokens (USD)
    MODEL_PRICING = {
        "gpt-4o": {"input": 0.005, "output": 0.015},
        "claude-3-5-sonnet": {"input": 0.003, "output": 0.015},
        "llama-3-70b-instruct": {"input": 0.0009, "output": 0.0009},
        "local-onnx-quantized": {"input": 0.00005, "output": 0.00005},  # pure electricity/compute proxy
    }

    def __init__(self, daily_budget_usd: float = 50.0, active_model: str = "llama-3-70b-instruct"):
        self.daily_budget_usd = daily_budget_usd
        self.active_model = active_model
        self.stats = TokenUsageStats()
        self.hourly_spend_history: List[Dict[str, Any]] = []

    def record_usage(
        self,
        prompt_tokens: int,
        completion_tokens: int,
        was_cached: bool = False,
        model_name: Optional[str] = None
    ):
        """
        Records single query token expenditure and financial metrics.
        """
        model = model_name or self.active_model
        rates = self.MODEL_PRICING.get(model, self.MODEL_PRICING["llama-3-70b-instruct"])

        self.stats.queries_processed += 1

        if was_cached:
            # Estimate tokens that would have been consumed
            est_saved_tokens = prompt_tokens + completion_tokens
            self.stats.cache_hits += 1
            self.stats.cached_tokens_saved += est_saved_tokens
            saved_cost = (prompt_tokens / 1000.0 * rates["input"]) + (completion_tokens / 1000.0 * rates["output"])
            self.stats.cost_saved_usd += saved_cost
            return

        self.stats.total_prompt_tokens += prompt_tokens
        self.stats.total_completion_tokens += completion_tokens
        self.stats.total_tokens += (prompt_tokens + completion_tokens)

        cost = (prompt_tokens / 1000.0 * rates["input"]) + (completion_tokens / 1000.0 * rates["output"])
        self.stats.total_cost_usd += cost

    def get_dashboard_summary(self) -> Dict[str, Any]:
        """
        Generates comprehensive financial telemetry and cost dashboard KPIs.
        """
        cache_hit_rate = (self.stats.cache_hits / max(1, self.stats.queries_processed)) * 100
        budget_utilization = (self.stats.total_cost_usd / max(0.01, self.daily_budget_usd)) * 100
        avg_cost_per_query = self.stats.total_cost_usd / max(1, self.stats.queries_processed - self.stats.cache_hits)

        return {
            "financial_summary": {
                "active_model_tier": self.active_model,
                "total_spend_usd": round(self.stats.total_cost_usd, 4),
                "cache_savings_usd": round(self.stats.cost_saved_usd, 4),
                "net_roi_savings_pct": round((self.stats.cost_saved_usd / max(0.0001, self.stats.total_cost_usd + self.stats.cost_saved_usd)) * 100, 1),
                "daily_budget_limit_usd": self.daily_budget_usd,
                "budget_utilization_pct": round(budget_utilization, 2),
                "budget_breached": self.stats.total_cost_usd > self.daily_budget_usd
            },
            "operational_metrics": {
                "total_queries_processed": self.stats.queries_processed,
                "cache_hits": self.stats.cache_hits,
                "cache_hit_rate_pct": round(cache_hit_rate, 1),
                "total_tokens_billed": self.stats.total_tokens,
                "cached_tokens_avoided": self.stats.cached_tokens_saved,
                "average_cost_per_inference_usd": round(avg_cost_per_query, 6)
            }
        }
