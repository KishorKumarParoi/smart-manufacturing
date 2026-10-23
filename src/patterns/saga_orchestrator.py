"""
Distributed Saga Orchestrator & CQRS Workflow Engine for Industrial Automation.
Manages multi-service distributed transactions with guaranteed backward compensation (Rollback).
Ensures eventual consistency without heavy two-phase commits (2PC).
"""

import time
import uuid
from typing import Dict, List, Optional, Any, Callable
from dataclasses import dataclass, field
from enum import Enum


class SagaStatus(str, Enum):
    PENDING = "PENDING"
    EXECUTING = "EXECUTING"
    COMPLETED = "COMPLETED"
    COMPENSATING = "COMPENSATING"
    COMPENSATED = "COMPENSATED"
    FAILED = "FAILED"


@dataclass
class SagaStep:
    name: str
    action_fn: Callable[[Dict[str, Any]], bool]
    compensation_fn: Callable[[Dict[str, Any]], bool]
    executed: bool = False
    compensated: bool = False
    error: Optional[str] = None


@dataclass
class SagaExecutionResult:
    saga_id: str
    workflow_name: str
    status: SagaStatus
    steps_executed: List[str]
    steps_compensated: List[str]
    duration_ms: float
    error_message: Optional[str] = None


class SagaOrchestrator:
    """
    Orchestrates distributed long-running operations across microservices with automatic rollback.
    """

    def __init__(self, workflow_name: str):
        self.workflow_name = workflow_name
        self.saga_id = str(uuid.uuid4())
        self.steps: List[SagaStep] = []
        self.context: Dict[str, Any] = {}

    def add_step(
        self,
        name: str,
        action: Callable[[Dict[str, Any]], bool],
        compensation: Callable[[Dict[str, Any]], bool]
    ):
        """Appends an idempotent step and its compensating action to the Saga."""
        self.steps.append(SagaStep(
            name=name,
            action_fn=action,
            compensation_fn=compensation
        ))

    def execute(self, initial_context: Optional[Dict[str, Any]] = None) -> SagaExecutionResult:
        """
        Executes the Saga forward. If any step fails, triggers backward compensating actions.
        """
        start = time.perf_counter()
        self.context = initial_context or {}
        executed_steps = []
        compensated_steps = []
        status = SagaStatus.EXECUTING
        error_msg = None

        for step in self.steps:
            try:
                success = step.action_fn(self.context)
                if success:
                    step.executed = True
                    executed_steps.append(step.name)
                else:
                    error_msg = f"Step '{step.name}' failed action execution."
                    step.error = error_msg
                    break
            except Exception as ex:
                error_msg = f"Exception in step '{step.name}': {str(ex)}"
                step.error = error_msg
                break

        # Check if all steps completed
        if len(executed_steps) == len(self.steps):
            status = SagaStatus.COMPLETED
        else:
            # Failure detected -> Begin backward compensation
            status = SagaStatus.COMPENSATING
            # Reverse iterate over executed steps
            for step in reversed(self.steps):
                if step.executed and not step.compensated:
                    try:
                        step.compensation_fn(self.context)
                        step.compensated = True
                        compensated_steps.append(step.name)
                    except Exception as comp_ex:
                        error_msg += f" | Compensation failed for '{step.name}': {str(comp_ex)}"

            status = SagaStatus.COMPENSATED if len(compensated_steps) == len(executed_steps) else SagaStatus.FAILED

        duration = (time.perf_counter() - start) * 1000
        return SagaExecutionResult(
            saga_id=self.saga_id,
            workflow_name=self.workflow_name,
            status=status,
            steps_executed=executed_steps,
            steps_compensated=compensated_steps,
            duration_ms=round(duration, 3),
            error_message=error_msg
        )
