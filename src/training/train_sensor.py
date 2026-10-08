import os
import argparse
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score
import mlflow
import mlflow.pytorch

from src.config import config
from src.data.generator import generate_sensor_telemetry
from src.data.dataset import SensorTelemetryDataset
from src.models.anomaly_detector import IndustrialSensorAutoencoder

def train_sensor_pipeline(epochs: int = 15, batch_size: int = 32, lr: float = 0.001):
    print(f"[*] Starting Industrial Sensor Anomaly Detection Training Pipeline")
    device = config.get_torch_device()
    print(f"[*] Compute Device: {device}")
    
    # 1. Generate & preprocess data
    df = generate_sensor_telemetry(n_samples=3000, anomaly_ratio=0.08)
    feature_cols = [
        "vibration_x", "vibration_y", "vibration_z",
        "temperature_c", "pressure_bar", "spindle_rpm", "acoustic_emission_db"
    ]
    
    # Train only on normal instances for unsupervised reconstruction
    normal_df = df[df["is_anomaly"] == 0]
    X_train_raw = normal_df[feature_cols].values
    
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train_raw)
    
    X_val_raw = df[feature_cols].values
    X_val_scaled = scaler.transform(X_val_raw)
    y_val = df["is_anomaly"].values
    
    train_dataset = SensorTelemetryDataset(X_train_scaled)
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    
    # 2. Setup Model & Optimizer
    model = IndustrialSensorAutoencoder(input_dim=len(feature_cols), latent_dim=3).to(device)
    criterion = nn.MSELoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-5)
    
    # 3. Setup MLflow
    try:
        mlflow.set_tracking_uri(config.mlflow_tracking_uri)
        mlflow.set_experiment("smart-manufacturing-sensor-anomalies")
    except Exception as e:
        print(f"[!] Warning: Could not connect to remote MLflow ({e}). Falling back to local file store.")
        mlflow.set_tracking_uri("file:///tmp/mlflow-runs")
        mlflow.set_experiment("smart-manufacturing-sensor-anomalies")
        
    with mlflow.start_run(run_name="sensor-autoencoder-gpu"):
        mlflow.log_params({
            "model_architecture": "Autoencoder",
            "epochs": epochs,
            "batch_size": batch_size,
            "learning_rate": lr,
            "device": str(device),
            "input_dim": len(feature_cols),
            "cloud_provider": config.current_cloud,
            "region": config.current_region
        })
        
        # 4. Training Loop
        model.train()
        for epoch in range(1, epochs + 1):
            epoch_loss = 0.0
            for batch_x in train_loader:
                batch_x = batch_x.to(device)
                optimizer.zero_grad()
                reconstructed, _ = model(batch_x)
                loss = criterion(reconstructed, batch_x)
                loss.backward()
                optimizer.step()
                epoch_loss += loss.item() * batch_x.size(0)
                
            epoch_loss /= len(train_dataset)
            if epoch % 5 == 0 or epoch == epochs:
                print(f"  [Epoch {epoch:02d}/{epochs:02d}] Reconstruction Loss: {epoch_loss:.6f}")
                mlflow.log_metric("train_reconstruction_loss", epoch_loss, step=epoch)
                
        # 5. Validation & Evaluation
        model.eval()
        val_tensor = torch.tensor(X_val_scaled, dtype=torch.float32).to(device)
        with torch.no_grad():
            scores = model.compute_anomaly_score(val_tensor).cpu().numpy()
            
        roc_auc = roc_auc_score(y_val, scores)
        threshold = float(np.percentile(scores[y_val == 0], 95))
        
        print(f"[*] Validation ROC-AUC Score: {roc_auc:.4f}")
        print(f"[*] Calibrated 95th Percentile Anomaly Threshold: {threshold:.6f}")
        
        mlflow.log_metric("val_roc_auc", roc_auc)
        mlflow.log_metric("calibrated_threshold", threshold)
        
        # 6. Save Artifacts & Register Model
        os.makedirs("models_checkpoints", exist_ok=True)
        checkpoint_path = "models_checkpoints/sensor_autoencoder.pt"
        torch.save({
            "model_state_dict": model.state_dict(),
            "scaler_mean": scaler.mean_,
            "scaler_scale": scaler.scale_,
            "threshold": threshold,
            "feature_cols": feature_cols
        }, checkpoint_path)
        
        mlflow.log_artifact(checkpoint_path)
        try:
            mlflow.pytorch.log_model(
                pytorch_model=model,
                artifact_path="model",
                registered_model_name="smart_mfg_sensor_autoencoder"
            )
            print("[✓] Model successfully logged and registered with MLflow Registry!")
        except Exception as e:
            print(f"[!] Warning: MLflow model registration skipped ({e})")
            
    return model, threshold

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=15)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=0.001)
    args = parser.parse_args()
    train_sensor_pipeline(epochs=args.epochs, batch_size=args.batch_size, lr=args.lr)
