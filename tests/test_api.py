import pytest
from fastapi.testclient import TestClient
from src.serving.app import app

client = TestClient(app)

def test_root_endpoint():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "OPERATIONAL"
    assert "service" in data

def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "HEALTHY"
    assert "cloud_provider" in data

def test_ready_endpoint():
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "READY"

def test_failover_status_endpoint():
    response = client.get("/failover/status")
    assert response.status_code == 200
    data = response.json()
    assert "primary_cloud" in data
    assert "secondary_cloud" in data

def test_sensor_inference():
    payload = {
        "machine_id": "CNC-MILL-TEST-01",
        "readings": [
            {
                "timestamp_sec": 1.0,
                "vibration_x": 0.45,
                "vibration_y": 0.40,
                "vibration_z": 0.30,
                "temperature_c": 64.5,
                "pressure_bar": 120.1,
                "spindle_rpm": 3005.0,
                "acoustic_emission_db": 45.2
            },
            {
                "timestamp_sec": 2.0,
                "vibration_x": 3.80, # Critical vibration anomaly
                "vibration_y": 2.90,
                "vibration_z": 1.50,
                "temperature_c": 110.0, # Overheating
                "pressure_bar": 70.0,
                "spindle_rpm": 2400.0,
                "acoustic_emission_db": 85.0 # High acoustic burst
            }
        ]
    }
    response = client.post("/predict/sensor", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["total_samples"] == 2
    assert "results" in data
    assert len(data["results"]) == 2

def test_vision_inference():
    payload = {
        "assembly_line_id": "LINE-VISION-01"
    }
    response = client.post("/predict/vision", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert "predicted_defect" in data
    assert "confidence" in data
    assert "defect_probabilities" in data

def test_metrics_endpoint():
    response = client.get("/metrics")
    assert response.status_code == 200
    assert b"smart_mfg_" in response.content
