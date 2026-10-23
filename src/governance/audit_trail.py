"""
Immutable Cryptographic Audit Trail with SHA-256 Hash Chaining.
Provides tamper-evident compliance logging for SOC 2 Type II, ISO 27001, and FDA 21 CFR Part 11.
Every model inference, administrative override, and guardrail tripwire is committed to an immutable ledger.
"""

import time
import hashlib
import json
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, field


@dataclass
class AuditEvent:
    sequence_id: int
    timestamp_utc: float
    tenant_id: str
    actor: str
    action: str
    resource: str
    payload_hash: str
    details: Dict[str, Any]
    prev_hash: str
    block_hash: str


class ImmutableAuditTrail:
    """
    Append-only cryptographically chained audit log.
    Any tampering with historical records invalidates the hash chain.
    """

    GENESIS_HASH = "0000000000000000000000000000000000000000000000000000000000000000"

    def __init__(self):
        self.ledger: List[AuditEvent] = []
        self._last_hash: str = self.GENESIS_HASH

    def log_event(
        self,
        tenant_id: str,
        actor: str,
        action: str,
        resource: str,
        details: Dict[str, Any]
    ) -> AuditEvent:
        """
        Appends an event to the audit ledger and computes its cryptographic hash signature.
        """
        seq = len(self.ledger) + 1
        now = time.time()
        payload_str = json.dumps(details, sort_keys=True)
        payload_hash = hashlib.sha256(payload_str.encode()).hexdigest()

        # Compute block hash linking to previous block
        block_content = f"{seq}:{now}:{tenant_id}:{actor}:{action}:{resource}:{payload_hash}:{self._last_hash}"
        block_hash = hashlib.sha256(block_content.encode()).hexdigest()

        event = AuditEvent(
            sequence_id=seq,
            timestamp_utc=now,
            tenant_id=tenant_id,
            actor=actor,
            action=action,
            resource=resource,
            payload_hash=payload_hash,
            details=details,
            prev_hash=self._last_hash,
            block_hash=block_hash
        )

        self.ledger.append(event)
        self._last_hash = block_hash
        return event

    def verify_integrity(self) -> Tuple[bool, Optional[str]]:
        """
        Validates the complete ledger from Genesis block to current head.
        Returns (is_valid, error_description).
        """
        expected_prev = self.GENESIS_HASH

        for idx, event in enumerate(self.ledger):
            # 1. Verify previous hash link
            if event.prev_hash != expected_prev:
                return False, f"Broken Chain: Block {event.sequence_id} prev_hash mismatch."

            # 2. Verify payload hash
            payload_str = json.dumps(event.details, sort_keys=True)
            recalculated_payload_hash = hashlib.sha256(payload_str.encode()).hexdigest()
            if recalculated_payload_hash != event.payload_hash:
                return False, f"Payload Tampered: Block {event.sequence_id} payload altered."

            # 3. Verify block hash
            block_content = f"{event.sequence_id}:{event.timestamp_utc}:{event.tenant_id}:{event.actor}:{event.action}:{event.resource}:{event.payload_hash}:{event.prev_hash}"
            recalculated_block_hash = hashlib.sha256(block_content.encode()).hexdigest()
            if recalculated_block_hash != event.block_hash:
                return False, f"Hash Invalid: Block {event.sequence_id} hash was recalculated differently."

            expected_prev = event.block_hash

        return True, None

    def get_events_for_tenant(self, tenant_id: str) -> List[AuditEvent]:
        """Returns filtered audit trail for a specific enterprise tenant."""
        return [e for e in self.ledger if e.tenant_id == tenant_id]
