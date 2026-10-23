# 📋 Model Card: Automated Optical Inspection (AOI) Deep CNN Defect Classifier (v2.2)

## 1. Model Overview
- **Model Name**: `ManufacturingDefectClassifier`
- **Model Version**: `2.2.0-prod`
- **Architecture**: 3-Block Deep Convolutional Neural Network with Adaptive Average Pooling and Dropout Regularization.
- **Framework**: PyTorch 2.4+ (TorchScript JIT exported, ONNX runtime compatible).
- **Target Hardware**: NVIDIA Tesla T4 / A10G / AWS Inferentia / Local Intel AVX-512.
- **Maintainer**: Principal Vision Engineering Team.

---

## 2. Intended Use & Class Taxonomy
- **Primary Use**: High-speed conveyor camera inspection on stamped sheet metal, machined casings, and semiconductor wafers.
- **Input Specifications**: RGB Tensor of shape $(B, 3, 64, 64)$ normalized to range $[0.0, 1.0]$.
- **Class Taxonomy (4 Mutually Exclusive Classes)**:
  1. `Class 0: Normal` (Pristine surface finish)
  2. `Class 1: Surface Crack` (Linear fractures $>0.5\text{mm}$, triggers robotic diversion to scrap)
  3. `Class 2: Pitting` (Micro-voids from hydraulic stamping cavitation)
  4. `Class 3: Burn Mark` (Friction scorch marks or excessive laser cut dwell time)
- **Decision Logic**: Softmax probability $P(y=c|x)$. If $c \ne 0$ and $P(y=c|x) \ge 0.85$, flag immediate conveyor halt.

---

## 3. Network Architecture
```mermaid
graph TD
    Input["Input: (3, 64, 64)"] --> Block1["Conv2d(3 -> 16, k=3, p=1) + BatchNorm2d + ReLU + MaxPool2d(2x2)"]
    Block1 --> Block2["Conv2d(16 -> 32, k=3, p=1) + BatchNorm2d + ReLU + MaxPool2d(2x2)"]
    Block2 --> Block3["Conv2d(32 -> 64, k=3, p=1) + BatchNorm2d + ReLU + MaxPool2d(2x2)"]
    Block3 --> Pool["AdaptiveAvgPool2d((4, 4))"]
    Pool --> Flatten["Flatten -> 1024 dims"]
    Flatten --> FC1["Linear(1024 -> 128) + ReLU + Dropout(0.4)"]
    FC1 --> FC2["Linear(128 -> 4) -> Softmax Probabilities"]
```

---

## 4. Performance & Evaluation Metrics
- **Accuracy**: $99.12\%$ on held-out 5,000 synthetic test inspection batch.
- **Inference Latency**: P95 $<12.4\text{ms}$ on GPU; P95 $<34.1\text{ms}$ on CPU.
- **Throughput**: 1,200 frames/sec per NVIDIA T4 GPU.
- **Quantization Gain**: INT8 Post-Training Quantization achieves a 38.4% reduction in GPU VRAM and latency with zero drop in macro F1-score ($0.989$).

---

## 5. Drift Monitoring & Retraining Triggers
- Track Population Stability Index (PSI) on convolutional feature activation maps.
- Retraining DAG triggered in Kubeflow if validation F1 drops below $0.95$ on rolling 7-day manufacturing audits.
