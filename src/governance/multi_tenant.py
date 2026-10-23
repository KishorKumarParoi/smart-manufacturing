"""
Multi-Tenant Isolation & Quota Governance Engine.
Enforces logical separation across manufacturing facilities, tenant rate-limiting, and resource governance.
"""

import time
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, field


@dataclass
class TenantContext:
    tenant_id: str
    organization_name: str
    tier: str  # "STANDARD", "ENTERPRISE", "DEDICATED"
    rate_limit_rpm: int
    daily_token_budget: int
    allowed_namespaces: List[str]
    current_minute_requests: int = 0
    current_day_tokens: int = 0
    last_reset_minute: float = field(default_factory=time.time)


class MultiTenantManager:
    """
    Manages multi-tenant isolation, authorization, and rate limit quotas.
    """

    DEFAULT_PLANS = {
        "STANDARD": {"rpm": 60, "tokens": 100000},
        "ENTERPRISE": {"rpm": 300, "tokens": 1000000},
        "DEDICATED": {"rpm": 1200, "tokens": 10000000},
    }

    def __init__(self):
        self.tenants: Dict[str, TenantContext] = {}

    def register_tenant(
        self,
        tenant_id: str,
        organization_name: str,
        tier: str = "ENTERPRISE"
    ) -> TenantContext:
        """Registers a new tenant with assigned tier limits."""
        plan = self.DEFAULT_PLANS.get(tier, self.DEFAULT_PLANS["ENTERPRISE"])
        ctx = TenantContext(
            tenant_id=tenant_id,
            organization_name=organization_name,
            tier=tier,
            rate_limit_rpm=plan["rpm"],
            daily_token_budget=plan["tokens"],
            allowed_namespaces=[f"mfg-{tenant_id}", "shared-sops"]
        )
        self.tenants[tenant_id] = ctx
        return ctx

    def verify_request_quota(
        self,
        tenant_id: str,
        estimated_tokens: int = 50
    ) -> Tuple[bool, Optional[str]]:
        """
        Validates tenant authorization and rate limit ceilings.
        Returns (is_allowed, denial_reason).
        """
        ctx = self.tenants.get(tenant_id)
        if not ctx:
            return False, f"Unauthorized: Tenant '{tenant_id}' is not registered."

        now = time.time()
        # Reset minute window
        if now - ctx.last_reset_minute > 60.0:
            ctx.current_minute_requests = 0
            ctx.last_reset_minute = now

        if ctx.current_minute_requests >= ctx.rate_limit_rpm:
            return False, f"Rate Limit Exceeded: Tenant '{tenant_id}' breached {ctx.rate_limit_rpm} RPM ceiling."

        if ctx.current_day_tokens + estimated_tokens > ctx.daily_token_budget:
            return False, f"Daily Budget Exhausted: Tenant '{tenant_id}' reached daily token limit."

        ctx.current_minute_requests += 1
        ctx.current_day_tokens += estimated_tokens
        return True, None
