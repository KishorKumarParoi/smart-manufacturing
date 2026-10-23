"""
Enterprise Prompt Injection & Jailbreak Defense Engine.
Implements layered heuristics for OWASP Top 10 for LLMs (LLM01: Prompt Injection).
Detects instruction overrides, delimiter attacks, base64 payloads, and system prompt leakage.
"""

import re
import base64
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, field


@dataclass
class InjectionCheckResult:
    is_safe: bool
    risk_score: float  # 0.0 (benign) to 1.0 (critical attack)
    detected_attack_types: List[str]
    matched_patterns: List[str]
    sanitized_prompt: str
    remediation_action: str  # "ALLOW", "FLAG", "BLOCK"


class PromptInjectionDetector:
    """
    Multi-stage detector for prompt injection, jailbreaks, and delimiter tampering.
    """

    OVERRIDE_PATTERNS = [
        (re.compile(r"ignore\s+(all\s+)?(previous|prior|above)\s+(instructions|directives|prompts)", re.IGNORECASE), "INSTRUCTION_OVERRIDE", 0.95),
        (re.compile(r"disregard\s+(any|all)\s+(preceding|previous)\s+rules", re.IGNORECASE), "INSTRUCTION_OVERRIDE", 0.95),
        (re.compile(r"you\s+are\s+now\s+(in\s+)?(DAN|developer|jailbreak|unrestricted|god)\s+mode", re.IGNORECASE), "JAILBREAK_ROLEPLAY", 0.90),
        (re.compile(r"from\s+now\s+on\s+you\s+(must|will)\s+act\s+as\s+an\s+unfiltered", re.IGNORECASE), "JAILBREAK_ROLEPLAY", 0.85),
        (re.compile(r"(print|reveal|display|leak|show|output)\s+(your\s+)?(initial|system|hidden)\s+(prompt|instructions)", re.IGNORECASE), "SYSTEM_PROMPT_LEAKAGE", 0.90),
        (re.compile(r"repeat\s+everything\s+(written|said)\s+(above|prior)", re.IGNORECASE), "SYSTEM_PROMPT_LEAKAGE", 0.80),
        (re.compile(r"what\s+are\s+your\s+(exact\s+)?(system\s+)?instructions\s*\?", re.IGNORECASE), "SYSTEM_PROMPT_LEAKAGE", 0.75),
        (re.compile(r"(bypass|disable|override)\s+(safety|content|policy)\s+(filters|guardrails)", re.IGNORECASE), "POLICY_CIRCUMVENTION", 0.95),
    ]

    DELIMITER_ATTACK_PATTERNS = [
        (re.compile(r"(?:\n|^)\s*(?:###\s*Instruction|###\s*System|\[INST\]|<\|im_start\|>system|<\|system\|>)", re.IGNORECASE), "DELIMITER_SPOOFING", 0.90),
        (re.compile(r"```(?:json|yaml|system|admin)?\s*(?:system|override|admin_command)", re.IGNORECASE), "MARKDOWN_HIJACKING", 0.80),
        (re.compile(r"<system_prompt>|<admin_override>", re.IGNORECASE), "TAG_INJECTION", 0.85),
    ]

    BASE64_PATTERN = re.compile(r"\b[A-Za-z0-9+/]{30,}={0,2}\b")

    def __init__(self, block_threshold: float = 0.70, flag_threshold: float = 0.40):
        self.block_threshold = block_threshold
        self.flag_threshold = flag_threshold

    def inspect(self, prompt: str) -> InjectionCheckResult:
        """
        Inspects incoming prompt against all heuristic attack signatures.
        """
        if not prompt or not prompt.strip():
            return InjectionCheckResult(
                is_safe=True,
                risk_score=0.0,
                detected_attack_types=[],
                matched_patterns=[],
                sanitized_prompt=prompt,
                remediation_action="ALLOW"
            )

        detected_types = []
        matched_patterns = []
        highest_score = 0.0

        # 1. Check Instruction Overrides
        for pattern, attack_name, score in self.OVERRIDE_PATTERNS:
            match = pattern.search(prompt)
            if match:
                detected_types.append(attack_name)
                matched_patterns.append(match.group(0))
                highest_score = max(highest_score, score)

        # 2. Check Delimiter Attacks
        for pattern, attack_name, score in self.DELIMITER_ATTACK_PATTERNS:
            match = pattern.search(prompt)
            if match:
                detected_types.append(attack_name)
                matched_patterns.append(match.group(0))
                highest_score = max(highest_score, score)

        # 3. Check Obfuscated / Base64 Encoded Payloads
        for b64_match in self.BASE64_PATTERN.finditer(prompt):
            candidate = b64_match.group(0)
            try:
                decoded = base64.b64decode(candidate, validate=True).decode("utf-8", errors="ignore")
                # Test decoded text for overrides
                for pattern, attack_name, _ in self.OVERRIDE_PATTERNS:
                    if pattern.search(decoded):
                        detected_types.append(f"OBFUSCATED_{attack_name}")
                        matched_patterns.append(f"b64({decoded[:30]}...)")
                        highest_score = max(highest_score, 0.95)
            except Exception:
                pass  # Not valid base64 or binary data

        # Remove duplicate attack types
        detected_types = list(set(detected_types))

        # Determine action
        if highest_score >= self.block_threshold:
            action = "BLOCK"
            is_safe = False
        elif highest_score >= self.flag_threshold:
            action = "FLAG"
            is_safe = True
        else:
            action = "ALLOW"
            is_safe = True

        # Sanitize prompt by stripping dangerous markdown control blocks if flagged
        sanitized = prompt
        if not is_safe or action == "FLAG":
            for pattern, _, _ in self.DELIMITER_ATTACK_PATTERNS:
                sanitized = pattern.sub("[SANITIZED_DELIMITER]", sanitized)

        return InjectionCheckResult(
            is_safe=is_safe,
            risk_score=round(highest_score, 3),
            detected_attack_types=detected_types,
            matched_patterns=matched_patterns,
            sanitized_prompt=sanitized,
            remediation_action=action
        )
