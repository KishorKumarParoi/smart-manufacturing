from pydantic import BaseModel, Field
from typing import List, Optional, Dict


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
