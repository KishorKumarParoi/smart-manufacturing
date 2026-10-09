import pytest

pytest.importorskip("torch")
import torch
import numpy as np
from src.models.anomaly_detector import IndustrialSensorAutoencoder
from src.models.defect_classifier import ManufacturingDefectClassifier
from src.data.generator import (
    generate_sensor_telemetry,
    generate_synthetic_defect_images,
)


def test_sensor_autoencoder_forward():
    model = IndustrialSensorAutoencoder(input_dim=7, latent_dim=3)
    dummy_input = torch.randn(8, 7)
    reconstructed, latent = model(dummy_input)

    assert reconstructed.shape == (8, 7)
    assert latent.shape == (8, 3)


def test_sensor_anomaly_score_computation():
    model = IndustrialSensorAutoencoder(input_dim=7, latent_dim=3)
    dummy_input = torch.randn(10, 7)
    scores = model.compute_anomaly_score(dummy_input)

    assert scores.shape == (10,)
    assert torch.all(scores >= 0.0)


def test_defect_classifier_forward():
    model = ManufacturingDefectClassifier(num_classes=4)
    dummy_img = torch.randn(4, 3, 64, 64)
    logits = model(dummy_img)

    assert logits.shape == (4, 4)


def test_defect_classifier_probabilities():
    model = ManufacturingDefectClassifier(num_classes=4)
    dummy_img = torch.randn(2, 3, 64, 64)
    probs = model.predict_probabilities(dummy_img)

    assert probs.shape == (2, 4)
    sum_probs = torch.sum(probs, dim=1)
    assert torch.allclose(sum_probs, torch.ones(2), atol=1e-4)


def test_telemetry_generator():
    df = generate_sensor_telemetry(n_samples=100)
    assert len(df) == 100
    assert "vibration_x" in df.columns
    assert "is_anomaly" in df.columns


def test_defect_image_generator():
    images, labels = generate_synthetic_defect_images(n_samples=20, img_size=64)
    assert images.shape == (20, 3, 64, 64)
    assert len(labels) == 20
