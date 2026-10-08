import os
import argparse
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, f1_score
import mlflow
import mlflow.pytorch

from src.config import config
from src.data.generator import generate_synthetic_defect_images
from src.data.dataset import DefectImageDataset
from src.models.defect_classifier import ManufacturingDefectClassifier

def train_vision_pipeline(epochs: int = 12, batch_size: int = 32, lr: float = 0.001):
    print(f"[*] Starting Manufacturing Defect Vision Inspection Training")
    device = config.get_torch_device()
    print(f"[*] Compute Device: {device}")
    
    # 1. Dataset Generation
    images, labels = generate_synthetic_defect_images(n_samples=800, img_size=64)
    X_train, X_val, y_train, y_val = train_test_split(images, labels, test_size=0.2, random_state=42, stratify=labels)
    
    train_dataset = DefectImageDataset(X_train, y_train)
    val_dataset = DefectImageDataset(X_val, y_val)
    
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=batch_size, shuffle=False)
    
    # 2. Model & Optimization
    model = ManufacturingDefectClassifier(num_classes=4).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    
    # 3. MLflow Tracking
    try:
        mlflow.set_tracking_uri(config.mlflow_tracking_uri)
        mlflow.set_experiment("smart-manufacturing-visual-inspection")
    except Exception as e:
        print(f"[!] Falling back to local file store for MLflow ({e})")
        mlflow.set_tracking_uri("file:///tmp/mlflow-runs")
        mlflow.set_experiment("smart-manufacturing-visual-inspection")
        
    with mlflow.start_run(run_name="aoi-defect-cnn-gpu"):
        mlflow.log_params({
            "model_type": "ManufacturingDefectClassifier_CNN",
            "epochs": epochs,
            "batch_size": batch_size,
            "learning_rate": lr,
            "num_classes": 4,
            "image_resolution": "64x64",
            "device": str(device),
            "cloud_provider": config.current_cloud
        })
        
        # 4. Training Loop
        for epoch in range(1, epochs + 1):
            model.train()
            running_loss = 0.0
            for imgs, lbls in train_loader:
                imgs, lbls = imgs.to(device), lbls.to(device)
                optimizer.zero_grad()
                outputs = model(imgs)
                loss = criterion(outputs, lbls)
                loss.backward()
                optimizer.step()
                running_loss += loss.item() * imgs.size(0)
                
            scheduler.step()
            train_loss = running_loss / len(train_dataset)
            
            # Validation
            model.eval()
            all_preds, all_targets = [], []
            with torch.no_grad():
                for imgs, lbls in val_loader:
                    imgs = imgs.to(device)
                    logits = model(imgs)
                    preds = torch.argmax(logits, dim=1).cpu().numpy()
                    all_preds.extend(preds)
                    all_targets.extend(lbls.numpy())
                    
            val_acc = accuracy_score(all_targets, all_preds)
            val_f1 = f1_score(all_targets, all_preds, average="weighted")
            
            if epoch % 3 == 0 or epoch == epochs:
                print(f"  [Epoch {epoch:02d}/{epochs:02d}] Loss: {train_loss:.4f} | Val Acc: {val_acc:.4f} | Val F1: {val_f1:.4f}")
                mlflow.log_metric("train_loss", train_loss, step=epoch)
                mlflow.log_metric("val_accuracy", val_acc, step=epoch)
                mlflow.log_metric("val_f1", val_f1, step=epoch)
                
        # 5. Checkpoint & Registry
        os.makedirs("models_checkpoints", exist_ok=True)
        checkpoint_path = "models_checkpoints/defect_classifier.pt"
        torch.save({
            "model_state_dict": model.state_dict(),
            "classes": ["normal", "crack", "pitting", "burn_mark"],
            "accuracy": val_acc,
            "f1": val_f1
        }, checkpoint_path)
        
        mlflow.log_artifact(checkpoint_path)
        try:
            mlflow.pytorch.log_model(
                pytorch_model=model,
                artifact_path="model",
                registered_model_name="smart_mfg_vision_defect_classifier"
            )
            print("[✓] Vision model registered in MLflow Model Registry.")
        except Exception as e:
            print(f"[!] Warning: MLflow model registration skipped ({e})")
            
    return model, val_acc

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=12)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=0.001)
    args = parser.parse_args()
    train_vision_pipeline(epochs=args.epochs, batch_size=args.batch_size, lr=args.lr)
