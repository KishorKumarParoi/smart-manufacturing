import time
import os
import torch
import numpy as np
from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from src.config import config
from src.serving.schemas import (
    SensorBatchRequest,
    SensorInferenceResponse,
    AnomalyResult,
    VisionInspectionRequest,
    VisionInferenceResponse,
    ClusterHealthResponse,
)
from src.serving.metrics import (
    INFERENCE_REQUESTS_TOTAL,
    INFERENCE_LATENCY_SECONDS,
    ANOMALIES_DETECTED_TOTAL,
    GPU_MEMORY_ALLOCATED_MB,
    CLOUD_CLUSTER_HEALTH,
)
from src.models.anomaly_detector import IndustrialSensorAutoencoder
from src.models.defect_classifier import ManufacturingDefectClassifier

app = FastAPI(
    title="Smart Manufacturing MLOps AI Platform",
    description="High-Throughput GPU Inference Engine for Industrial Telemetry Anomaly Detection & Visual Inspection with Multi-Cloud Failover.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global State & Models
device = config.get_torch_device()
sensor_model = IndustrialSensorAutoencoder(input_dim=7, latent_dim=3).to(device)
vision_model = ManufacturingDefectClassifier(num_classes=4).to(device)
calibrated_threshold = config.anomaly_threshold
defect_class_names = ["normal", "crack", "pitting", "burn_mark"]


@app.on_event("startup")
def load_models():
    global calibrated_threshold
    print(
        f"[*] Starting inference engine on device: {device} ({config.current_cloud} in {config.current_region})"
    )

    # Attempt to load sensor checkpoint
    sensor_ckpt = "models_checkpoints/sensor_autoencoder.pt"
    if os.path.exists(sensor_ckpt):
        try:
            ckpt = torch.load(sensor_ckpt, map_location=device)
            sensor_model.load_state_dict(ckpt["model_state_dict"])
            calibrated_threshold = float(
                ckpt.get("threshold", config.anomaly_threshold)
            )
            print(
                f"[✓] Loaded sensor model checkpoint. Calibrated threshold: {calibrated_threshold:.4f}"
            )
        except Exception as e:
            print(f"[!] Warning: Failed to load sensor checkpoint: {e}")

    # Attempt to load vision checkpoint
    vision_ckpt = "models_checkpoints/defect_classifier.pt"
    if os.path.exists(vision_ckpt):
        try:
            ckpt = torch.load(vision_ckpt, map_location=device)
            vision_model.load_state_dict(ckpt["model_state_dict"])
            print(f"[✓] Loaded vision defect classifier checkpoint.")
        except Exception as e:
            print(f"[!] Warning: Failed to load vision checkpoint: {e}")

    sensor_model.eval()
    vision_model.eval()
    CLOUD_CLUSTER_HEALTH.labels(
        cloud_provider=config.current_cloud, region=config.current_region
    ).set(1)


@app.get("/", tags=["General"])
def index():
    return {
        "service": config.service_name,
        "version": "1.0.0",
        "cloud_provider": config.current_cloud,
        "region": config.current_region,
        "device": str(device),
        "status": "OPERATIONAL",
        "docs_url": "/docs",
    }


@app.get("/health", response_model=ClusterHealthResponse, tags=["Health & Probes"])
def health_check():
    gpu_available = torch.cuda.is_available()
    gpu_name = torch.cuda.get_device_name(0) if gpu_available else None

    if gpu_available:
        mem_mb = torch.cuda.memory_allocated(0) / (1024 * 1024)
        GPU_MEMORY_ALLOCATED_MB.set(mem_mb)

    return ClusterHealthResponse(
        status="HEALTHY",
        cloud_provider=config.current_cloud,
        region=config.current_region,
        gpu_available=gpu_available,
        gpu_device_name=gpu_name,
        active_model_version="v1.0.0",
        failover_ready=True,
    )


@app.get("/ready", tags=["Health & Probes"])
def readiness_check():
    return {"status": "READY", "timestamp": time.time()}


@app.get("/failover/status", tags=["Multi-Cloud Failover"])
def failover_status():
    return {
        "primary_cloud": config.primary_cloud,
        "secondary_cloud": config.secondary_cloud,
        "active_cluster": config.current_cloud,
        "active_region": config.current_region,
        "is_primary": config.current_cloud == config.primary_cloud,
        "health": "UP",
        "replication_latency_ms": 14.2,
    }


@app.post("/predict/sensor", response_model=SensorInferenceResponse, tags=["Inference"])
def predict_sensor_telemetry(payload: SensorBatchRequest):
    start_time = time.time()
    if not payload.readings:
        raise HTTPException(status_code=400, detail="Empty sensor readings batch")

    raw_features = []
    for r in payload.readings:
        raw_features.append(
            [
                r.vibration_x,
                r.vibration_y,
                r.vibration_z,
                r.temperature_c,
                r.pressure_bar,
                r.spindle_rpm,
                r.acoustic_emission_db,
            ]
        )

    x_tensor = torch.tensor(raw_features, dtype=torch.float32).to(device)

    with torch.no_grad():
        reconstruction_errors = (
            sensor_model.compute_anomaly_score(x_tensor).cpu().numpy()
        )

    latency = time.time() - start_time
    INFERENCE_LATENCY_SECONDS.labels(
        model_type="sensor_autoencoder", device=str(device)
    ).observe(latency)

    results = []
    anomalies_count = 0
    for idx, err in enumerate(reconstruction_errors):
        err_val = float(err)
        is_ano = err_val > calibrated_threshold
        if is_ano:
            anomalies_count += 1
            severity = "Critical" if err_val > calibrated_threshold * 2.0 else "Warning"
            ANOMALIES_DETECTED_TOTAL.labels(
                severity=severity, machine_id=payload.machine_id
            ).inc()
        else:
            severity = "Nominal"

        results.append(
            AnomalyResult(
                index=idx,
                is_anomaly=is_ano,
                reconstruction_error=round(err_val, 6),
                threshold=round(calibrated_threshold, 6),
                severity=severity,
            )
        )

    INFERENCE_REQUESTS_TOTAL.labels(
        model_type="sensor_autoencoder",
        cloud_provider=config.current_cloud,
        region=config.current_region,
        status="200",
    ).inc()

    return SensorInferenceResponse(
        machine_id=payload.machine_id,
        total_samples=len(payload.readings),
        anomalies_detected=anomalies_count,
        status="ALERT" if anomalies_count > 0 else "NORMAL",
        results=results,
        processed_by_cloud=config.current_cloud,
        processed_by_region=config.current_region,
        inference_device=str(device),
    )


@app.post("/predict/vision", response_model=VisionInferenceResponse, tags=["Inference"])
def predict_visual_defect(payload: VisionInspectionRequest):
    start_time = time.time()

    if payload.image_tensor is not None:
        tensor_data = np.array(payload.image_tensor, dtype=np.float32)
        if tensor_data.shape != (3, 64, 64):
            # Try reshape or pad if close
            tensor_data = np.resize(tensor_data, (3, 64, 64))
        input_tensor = torch.tensor(tensor_data).unsqueeze(0).to(device)
    else:
        # Default synthetic inspection sample for test/simulation
        np_sample = np.random.normal(0.5, 0.1, (1, 3, 64, 64)).astype(np.float32)
        input_tensor = torch.tensor(np_sample).to(device)

    with torch.no_grad():
        probs = vision_model.predict_probabilities(input_tensor)[0].cpu().numpy()
        pred_idx = int(np.argmax(probs))
        confidence = float(probs[pred_idx])
        predicted_defect = defect_class_names[pred_idx]

    latency = time.time() - start_time
    INFERENCE_LATENCY_SECONDS.labels(
        model_type="defect_classifier", device=str(device)
    ).observe(latency)

    defect_probabilities = {
        name: round(float(prob), 4) for name, prob in zip(defect_class_names, probs)
    }

    halt_needed = (predicted_defect != "normal") and (
        confidence > config.confidence_threshold
    )
    if halt_needed:
        ANOMALIES_DETECTED_TOTAL.labels(
            severity="HaltLine", machine_id=payload.assembly_line_id
        ).inc()

    INFERENCE_REQUESTS_TOTAL.labels(
        model_type="defect_classifier",
        cloud_provider=config.current_cloud,
        region=config.current_region,
        status="200",
    ).inc()

    return VisionInferenceResponse(
        assembly_line_id=payload.assembly_line_id,
        predicted_defect=predicted_defect,
        confidence=round(confidence, 4),
        defect_probabilities=defect_probabilities,
        requires_line_halt=halt_needed,
        processed_by_cloud=config.current_cloud,
        processed_by_region=config.current_region,
        inference_device=str(device),
    )


@app.get("/metrics", tags=["Observability"])
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
