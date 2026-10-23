"""
Cryptographic Idempotency Key Manager & Replay Defense.
Ensures distributed RPC and API requests cannot trigger duplicate mechanical or financial side effects.
"""

import time
import hashlib
from typing import Dict, Optional, Any, Tuple
from dataclasses import dataclass
from enum import Enum


class IdempotencyState(str, Enum):
    IN_FLIGHT = "IN_FLIGHT"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


@dataclass
class IdempotentRecord:
    key: str
    state: IdempotencyState
    response_payload: Optional[Dict[str, Any]]
    created_at: float
    ttl_seconds: float = 86400.0  # 24 hours default


class IdempotencyManager:
    """
    Validates idempotency keys and prevents duplicate side effects in APIs and workers.
    """

    def __init__(self, default_ttl_seconds: float = 86400.0):
        self.default_ttl = default_ttl_seconds
        self._store: Dict[str, IdempotentRecord] = {}

    def acquire_lock(self, idempotency_key: str) -> Tuple[bool, Optional[IdempotentRecord]]:
        """
        Attempts to acquire an execution lock for a given idempotency key.
        Returns:
            (can_proceed, existing_record)
        """
        now = time.time()
        record = self._store.get(idempotency_key)

        if record:
            # Check for TTL expiry
            if now - record.created_at > record.ttl_seconds:
                del self._store[idempotency_key]
            else:
                # Key already exists: Cannot proceed
                return False, record

        # Register IN_FLIGHT record
        new_record = IdempotentRecord(
            key=idempotency_key,
            state=IdempotencyState.IN_FLIGHT,
            response_payload=None,
            created_at=now,
            ttl_seconds=self.default_ttl
        )
        self._store[idempotency_key] = new_record
        return True, None

    def commit_result(self, idempotency_key: str, response_payload: Dict[str, Any]):
        """Commits final result against the idempotency key for replay delivery."""
        if idempotency_key in self._store:
            record = self._store[idempotency_key]
            record.state = IdempotencyState.COMPLETED
            record.response_payload = response_payload

    def release_on_failure(self, idempotency_key: str):
        """Releases the lock on failure so transient errors can be safely retried."""
        if idempotency_key in self._store:
            del self._store[idempotency_key]
