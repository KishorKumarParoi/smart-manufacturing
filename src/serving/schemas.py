from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any


class SensorTelemetryItem(BaseModel):
    timestamp_sec: Optional[float] = 0.0
    vibration_x: float = Field(..., description="Vibration on X-axis in g")
    vibration_y: float = Field(..., description="Vibration on Y-axis in g")
    vibration_z: float = Field(..., description="Vibration on Z-axis in g")
    temperature_c: float = Field(
        ..., description="Bearing / spindle temperature in Celsius"
    )
    pressure_bar: float = Field(..., description="Hydraulic system pressure in bar")
    spindle_rpm: float = Field(..., description="Motor rotation speed in RPM")
    acoustic_emission_db: float = Field(
        ..., description="High-frequency acoustic emissions in dB"
    )


class SensorBatchRequest(BaseModel):
    machine_id: str = "CNC-MILL-ALPHA-01"
    readings: List[SensorTelemetryItem]


class AnomalyResult(BaseModel):
    index: int
    is_anomaly: bool
    reconstruction_error: float
    threshold: float
    severity: str  # Nominal, Warning, Critical


class SensorInferenceResponse(BaseModel):
    machine_id: str
    total_samples: int
    anomalies_detected: int
    status: str
    results: List[AnomalyResult]
    processed_by_cloud: str
    processed_by_region: str
    inference_device: str


class VisionInspectionRequest(BaseModel):
    assembly_line_id: str = "LINE-SURFACE-INSPECT-04"
    image_base64: Optional[str] = None
    # Support direct normalized tensor or test matrix
    image_tensor: Optional[List[List[List[float]]]] = None


class VisionInferenceResponse(BaseModel):
    assembly_line_id: str
    predicted_defect: str
    confidence: float
    defect_probabilities: Dict[str, float]
    requires_line_halt: bool
    processed_by_cloud: str
    processed_by_region: str
    inference_device: str


class ClusterHealthResponse(BaseModel):
    status: str
    cloud_provider: str
    region: str
    gpu_available: bool
    gpu_device_name: Optional[str]
    active_model_version: str
    failover_ready: bool


class RAGQueryRequest(BaseModel):
    query: str
    tenant_id: str = "tenant-mfg-01"
    variant: str = "A"  # "A" (Dense baseline) or "B" (Hybrid reranked)
    bypass_cache: bool = False


class RAGQueryResponse(BaseModel):
    query: str
    response: str
    citations: List[Dict[str, Any]]
    cached: bool
    latency_ms: float
    token_usage: Dict[str, int]
    passed_guardrails: bool
    geval_score: Optional[float] = None
    variant: str


class GuardrailValidationRequest(BaseModel):
    text: str
    enforce_topic_gating: bool = True


class GuardrailValidationResponse(BaseModel):
    passed: bool
    rejection_reason: Optional[str]
    sanitized_text: str
    pii_entities_detected: int
    injection_risk_score: float
    remediation_action: str
    latency_ms: float


class OutboxEventRequest(BaseModel):
    aggregate_type: str = "MACHINE"
    aggregate_id: str = "CNC-SPINDLE-01"
    event_type: str = "CRITICAL_VIBRATION_EXCEEDED"
    payload: Dict[str, Any]
    idempotency_key: Optional[str] = None


class SagaTriggerRequest(BaseModel):
    machine_id: str = "CNC-MILL-ALPHA-01"
    anomaly_severity: str = "CRITICAL"
    component_part_number: str = "BEARING-SKF-6205"
    simulated_failure_step: Optional[str] = None  # e.g., "inventory_reservation"

