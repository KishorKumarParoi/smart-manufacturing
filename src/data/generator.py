import numpy as np
import pandas as pd
from typing import Tuple, Dict


def generate_sensor_telemetry(
    n_samples: int = 2000, anomaly_ratio: float = 0.08, random_state: int = 42
) -> pd.DataFrame:
    """
    Generate realistic multi-sensor telemetry for industrial CNC / rotating machinery:
    - Vibration X, Y, Z (g)
    - Bearing Temperature (Celsius)
    - Hydraulic Pressure (bar)
    - Spindle RPM (rev/min)
    - Acoustic Emission (dB)
    """
    np.random.seed(random_state)
    t = np.linspace(0, 100, n_samples)

    # Baseline nominal operation
    vib_x = 0.5 * np.sin(2 * np.pi * 0.2 * t) + np.random.normal(0, 0.05, n_samples)
    vib_y = 0.4 * np.cos(2 * np.pi * 0.2 * t) + np.random.normal(0, 0.05, n_samples)
    vib_z = 0.3 * np.sin(2 * np.pi * 0.1 * t) + np.random.normal(0, 0.04, n_samples)
    temp = (
        65.0 + 3.0 * np.sin(2 * np.pi * 0.01 * t) + np.random.normal(0, 0.5, n_samples)
    )
    pressure = 120.0 + np.random.normal(0, 2.0, n_samples)
    rpm = (
        3000.0
        + 20.0 * np.sin(2 * np.pi * 0.05 * t)
        + np.random.normal(0, 5.0, n_samples)
    )
    acoustic = 45.0 + np.random.normal(0, 1.5, n_samples)

    is_anomaly = np.zeros(n_samples, dtype=int)
    n_anomalies = int(n_samples * anomaly_ratio)
    anomaly_indices = np.random.choice(n_samples, size=n_anomalies, replace=False)

    # Inject failure patterns (bearing degradation, thermal runaway, cavitation)
    for idx in anomaly_indices:
        is_anomaly[idx] = 1
        fault_type = np.random.choice(
            ["bearing_failure", "thermal_runaway", "cavitation"]
        )
        if fault_type == "bearing_failure":
            vib_x[idx] += np.random.uniform(1.2, 2.5)
            vib_y[idx] += np.random.uniform(1.0, 2.0)
            acoustic[idx] += np.random.uniform(15.0, 30.0)
        elif fault_type == "thermal_runaway":
            temp[idx] += np.random.uniform(25.0, 45.0)
            pressure[idx] -= np.random.uniform(20.0, 40.0)
        elif fault_type == "cavitation":
            pressure[idx] += np.random.uniform(30.0, 60.0)
            rpm[idx] -= np.random.uniform(200.0, 500.0)
            acoustic[idx] += np.random.uniform(20.0, 35.0)

    df = pd.DataFrame(
        {
            "timestamp_sec": t,
            "vibration_x": vib_x,
            "vibration_y": vib_y,
            "vibration_z": vib_z,
            "temperature_c": temp,
            "pressure_bar": pressure,
            "spindle_rpm": rpm,
            "acoustic_emission_db": acoustic,
            "is_anomaly": is_anomaly,
        }
    )
    return df


def generate_synthetic_defect_images(
    n_samples: int = 500, img_size: int = 64
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Generate synthetic optical surface inspection images with labeled defect classes:
    0: Normal / Nominal Surface
    1: Crack Defect
    2: Pitting Corrosion
    3: Surface Burn Mark
    """
    np.random.seed(42)
    images = np.zeros((n_samples, 3, img_size, img_size), dtype=np.float32)
    labels = np.random.randint(0, 4, size=n_samples)

    for i in range(n_samples):
        # Base metallic texture
        base = np.random.normal(0.5, 0.05, (3, img_size, img_size))
        lbl = labels[i]

        if lbl == 1:  # Crack (linear dark line)
            x0, y0 = np.random.randint(10, 50, size=2)
            length = np.random.randint(15, 30)
            for step in range(length):
                px = min(img_size - 1, x0 + step)
                py = min(img_size - 1, y0 + int(0.5 * step + np.random.randint(-1, 2)))
                base[:, px, py] = 0.05
        elif lbl == 2:  # Pitting (scattered dark spots)
            num_pits = np.random.randint(5, 12)
            for _ in range(num_pits):
                px, py = np.random.randint(10, 54, size=2)
                base[
                    :,
                    max(0, px - 1) : min(img_size, px + 2),
                    max(0, py - 1) : min(img_size, py + 2),
                ] = 0.1
        elif lbl == 3:  # Burn mark (high contrast discolored oval)
            cx, cy = np.random.randint(20, 44, size=2)
            r = np.random.randint(5, 12)
            y, x = np.ogrid[:img_size, :img_size]
            dist_from_center = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            mask = dist_from_center <= r
            base[0, mask] = 0.85
            base[1, mask] = 0.2
            base[2, mask] = 0.1

        images[i] = np.clip(base, 0.0, 1.0)

    return images, labels
