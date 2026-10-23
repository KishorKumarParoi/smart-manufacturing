"""
Enterprise Policy & Guardrails Engine for Industrial AI Systems.
Implements topic gating, safety constraints, hallucination tripwires, and output verification.
Inspired by NVIDIA NeMo Guardrails architecture with sub-millisecond evaluation latency.
"""

import re
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass
from src.security_guardrails.pii_filter import PIIFilter, AnonymizationResult
from src.security_guardrails.injection_defense import PromptInjectionDetector, InjectionCheckResult


@dataclass
class GuardrailDecision:
    passed: bool
    rejection_reason: Optional[str] = None
    sanitized_input: str = ""
    pii_metadata: Optional[AnonymizationResult] = None
    injection_metadata: Optional[InjectionCheckResult] = None
    latency_ms: float = 0.0


class PolicyGuardrailEngine:
    """
    Enforces enterprise policy guardrails on input queries and generated responses.
    """

    ALLOWED_TOPIC_KEYWORDS = {
        "vibration", "temperature", "spindle", "cnc", "bearing", "torque", "anomaly",
        "defect", "inspection", "optical", "camera", "crack", "pitting", "burn", "maintenance",
        "sensor", "telemetry", "pressure", "rpm", "lubrication", "hydraulic", "safety",
        "interlock", "failover", "cloud", "aws", "gcp", "kubernetes", "sop", "work order",
        "equipment", "motor", "conveyor", "acoustic", "scada", "plc", "modbus", "manufacturing",
        "calibration", "tolerance", "milling", "lathe", "robot", "alarm", "emergency", "stop"
    }

    FORBIDDEN_OUTPUT_INSTRUCTIONS = [
        re.compile(r"(disable|bypass|deactivate|turn\s*off)\s+(the\s+)?(safety\s+interlock|emergency\s+stop|e-stop|thermal\s+cutoff|pressure\s+relief)", re.IGNORECASE),
        re.compile(r"(ignore|suppress)\s+(critical\s+vibration|overheating\s+alarm|fire\s+warning)", re.IGNORECASE),
        re.compile(r"operate\s+(spindle|motor)\s+above\s+maximum\s+(rated|safe)\s+rpm", re.IGNORECASE),
    ]

    def __init__(self, enforce_topic_gating: bool = True):
        self.enforce_topic_gating = enforce_topic_gating
        self.pii_filter = PIIFilter()
        self.injection_detector = PromptInjectionDetector()

    def validate_input(self, prompt: str) -> GuardrailDecision:
        """
        Executes multi-stage input validation:
        1. Injection defense check
        2. PII filtering and masking
        3. Industrial topic relevance gating
        """
        import time
        start = time.perf_counter()

        # Step 1: Prompt Injection Check
        injection_res = self.injection_detector.inspect(prompt)
        if not injection_res.is_safe:
            duration = (time.perf_counter() - start) * 1000
            return GuardrailDecision(
                passed=False,
                rejection_reason=f"Security Policy Violation: Prompt injection detected ({', '.join(injection_res.detected_attack_types)}).",
                sanitized_input="",
                injection_metadata=injection_res,
                latency_ms=round(duration, 3)
            )

        # Step 2: PII Filtering
        pii_res = self.pii_filter.filter(prompt)
        sanitized_query = pii_res.sanitized_text

        # Step 3: Industrial Topic Gating
        if self.enforce_topic_gating:
            words = set(re.findall(r"\b\w+\b", prompt.lower()))
            has_relevant_topic = bool(words.intersection(self.ALLOWED_TOPIC_KEYWORDS))

            # Allow short greeting or metadata queries
            if not has_relevant_topic and len(words) > 3:
                duration = (time.perf_counter() - start) * 1000
                return GuardrailDecision(
                    passed=False,
                    rejection_reason="Topic Policy Refusal: Query is off-topic. This AI system only assists with industrial manufacturing, machinery health, and plant operations.",
                    sanitized_input="",
                    pii_metadata=pii_res,
                    injection_metadata=injection_res,
                    latency_ms=round(duration, 3)
                )

        duration = (time.perf_counter() - start) * 1000
        return GuardrailDecision(
            passed=True,
            rejection_reason=None,
            sanitized_input=sanitized_query,
            pii_metadata=pii_res,
            injection_metadata=injection_res,
            latency_ms=round(duration, 3)
        )

    def validate_output(self, response_text: str) -> Tuple[bool, Optional[str]]:
        """
        Scrutinizes model output against mechanical safety violations and harmful recommendations.
        """
        for pattern in self.FORBIDDEN_OUTPUT_INSTRUCTIONS:
            if pattern.search(response_text):
                return False, "Dangerous Mechanical Instruction Detected: Output recommends bypassing safety systems or operating beyond safety limits."
        return True, None
