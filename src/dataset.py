import torch
from torch.utils.data import Dataset
import numpy as np


class SensorTelemetryDataset(Dataset):
    def __init__(self, features: np.ndarray, labels: np.ndarray = None):
        self.features = torch.tensor(features, dtype=torch.float32)
        self.labels = (
            torch.tensor(labels, dtype=torch.float32) if labels is not None else None
        )

    def __len__(self) -> int:
        return len(self.features)

    def __getitem__(self, idx: int):
        if self.labels is not None:
            return self.features[idx], self.labels[idx]
        return self.features[idx]


class DefectImageDataset(Dataset):
    def __init__(self, images: np.ndarray, labels: np.ndarray):
        self.images = torch.tensor(images, dtype=torch.float32)
        self.labels = torch.tensor(labels, dtype=torch.long)

    def __len__(self) -> int:
        return len(self.images)

    def __getitem__(self, idx: int):
        return self.images[idx], self.labels[idx]
