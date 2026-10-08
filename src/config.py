import os
import torch
from pydantic import BaseModel, Field

class AppConfig(BaseModel):
    app_env: str = Field(default_factory=lambda: os.getenv("APP_ENV", "production"))
    service_name: str = Field(default_factory=lambda: os.getenv("SERVICE_NAME", "smart-manufacturing-inference-engine"))
    log_level: str = Field(default_factory=lambda: os.getenv("LOG_LEVEL", "INFO"))
    
    # Cloud & Failover
    primary_cloud: str = Field(default_factory=lambda: os.getenv("PRIMARY_CLOUD", "aws"))
    secondary_cloud: str = Field(default_factory=lambda: os.getenv("SECONDARY_CLOUD", "gcp"))
    current_cloud: str = Field(default_factory=lambda: os.getenv("CURRENT_CLOUD", "aws"))
    current_region: str = Field(default_factory=lambda: os.getenv("CURRENT_REGION", "us-east-1"))
    
    # MLflow
    mlflow_tracking_uri: str = Field(default_factory=lambda: os.getenv("MLFLOW_TRACKING_URI", "http://mlflow:5000"))
    mlflow_experiment_name: str = Field(default_factory=lambda: os.getenv("MLFLOW_EXPERIMENT_NAME", "smart-manufacturing-inspection"))
    mlflow_model_name: str = Field(default_factory=lambda: os.getenv("MLFLOW_MODEL_NAME", "industrial_defect_detector"))
    
    # Storage Buckets
    aws_s3_bucket: str = Field(default_factory=lambda: os.getenv("AWS_S3_BUCKET_NAME", "smart-mfg-mlops-artifacts-us-east-1"))
    gcp_gcs_bucket: str = Field(default_factory=lambda: os.getenv("GCP_GCS_BUCKET_NAME", "smart-mfg-mlops-artifacts-us-central1"))
    
    # GPU & Compute Engine
    device_preference: str = Field(default_factory=lambda: os.getenv("DEVICE", "cuda"))
    anomaly_threshold: float = Field(default_factory=lambda: float(os.getenv("ANOMALY_THRESHOLD", "0.68")))
    confidence_threshold: float = Field(default_factory=lambda: float(os.getenv("CONFIDENCE_THRESHOLD", "0.85")))
    
    def get_torch_device(self) -> torch.device:
        if self.device_preference == "cuda" and torch.cuda.is_available():
            return torch.device("cuda")
        elif torch.backends.mps.is_available():
            return torch.device("mps")
        return torch.device("cpu")

config = AppConfig()
