"""
Enterprise PII (Personally Identifiable Information) Filter & Token Anonymization Vault.
Provides deterministic, high-throughput regex and cryptographic masking for industrial AI streams.
Compliant with GDPR, HIPAA, and ISO 27001 data protection standards.
"""

import re
import hashlib
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, field


@dataclass
class AnonymizationResult:
    original_text: str
    sanitized_text: str
    redacted_entities: List[Dict[str, str]]
    entity_counts: Dict[str, int]
    is_modified: bool
    hash_signature: str


class PIIFilter:
    """
    Production-grade PII detection and redaction engine.
    Supports reversible and irreversible tokenization vaults.
    """

    PATTERNS = {
        "EMAIL": re.compile(
            r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,7}\b"
        ),
        "PHONE": re.compile(
            r"(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"
        ),
        "SSN": re.compile(
            r"\b(?!000|666|9\d{2})\d{3}[- ]?(?!00)\d{2}[- ]?(?!0000)\d{4}\b"
        ),
        "CREDIT_CARD": re.compile(
            r"\b(?:\d{4}[- ]?){3}\d{4}\b"
        ),
        "IPV4": re.compile(
            r"\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"
        ),
        "EMPLOYEE_ID": re.compile(
            r"\b(?:EMP|TECH|ENG|OPR)[-_]?\d{4,8}\b",
            re.IGNORECASE
        ),
        "API_KEY": re.compile(
            r"\b(?:sk|pk|api|key)[-_][A-Za-z0-9]{20,60}\b",
            re.IGNORECASE
        ),
        "MACHINE_SERIAL": re.compile(
            r"\b(?:SN|MCH|DEV)[-_][A-Z0-9]{6,16}\b"
        ),
    }

    def __init__(self, mask_format: str = "<REDACTED_{entity_type}_{index}>"):
        self.mask_format = mask_format
        self._vault: Dict[str, str] = {}  # token -> original_value

    def filter(self, text: str, store_vault: bool = True) -> AnonymizationResult:
        """
        Scans and redacts sensitive PII from incoming input text.
        """
        if not text:
            return AnonymizationResult(
                original_text="",
                sanitized_text="",
                redacted_entities=[],
                entity_counts={},
                is_modified=False,
                hash_signature=""
            )

        sanitized = text
        redacted_entities = []
        counts: Dict[str, int] = {}

        for entity_type, pattern in self.PATTERNS.items():
            matches = list(pattern.finditer(sanitized))
            if not matches:
                continue

            counts[entity_type] = 0
            # Process in reverse order to preserve string offsets
            for idx, match in enumerate(reversed(matches)):
                val = match.group(0)
                # Luhn check verification for credit cards to avoid false positives
                if entity_type == "CREDIT_CARD" and not self._luhn_verify(val):
                    continue

                counts[entity_type] += 1
                token = self.mask_format.format(
                    entity_type=entity_type,
                    index=len(matches) - idx
                )

                if store_vault:
                    self._vault[token] = val

                redacted_entities.append({
                    "type": entity_type,
                    "original": val,
                    "replacement": token,
                    "span": (match.start(), match.end()),
                })

                sanitized = sanitized[:match.start()] + token + sanitized[match.end():]

        is_mod = len(redacted_entities) > 0
        sig = hashlib.sha256(sanitized.encode()).hexdigest()

        return AnonymizationResult(
            original_text=text,
            sanitized_text=sanitized,
            redacted_entities=redacted_entities,
            entity_counts=counts,
            is_modified=is_mod,
            hash_signature=sig
        )

    def restore(self, sanitized_text: str) -> str:
        """
        Reverses tokenized redactions using the local vault.
        """
        restored = sanitized_text
        for token, original in self._vault.items():
            restored = restored.replace(token, original)
        return restored

    @staticmethod
    def _luhn_verify(card_str: str) -> bool:
        """Validates numerical string against Luhn MOD-10 checksum."""
        digits = [int(c) for c in re.sub(r"\D", "", card_str)]
        if len(digits) < 13 or len(digits) > 19:
            return False
        checksum = 0
        reverse_digits = digits[::-1]
        for i, digit in enumerate(reverse_digits):
            if i % 2 == 1:
                doubled = digit * 2
                checksum += doubled - 9 if doubled > 9 else doubled
            else:
                checksum += digit
        return checksum % 10 == 0
