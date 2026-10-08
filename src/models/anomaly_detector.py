import torch
import torch.nn as nn
from typing import Tuple

class IndustrialSensorAutoencoder(nn.Module):
    """
    Symmetric Autoencoder for unsupervised reconstruction of multi-channel sensor telemetry.
    Reconstruction error (MSE) above threshold denotes anomalous mechanical state.
    """
    def __init__(self, input_dim: int = 7, latent_dim: int = 3):
        super().__init__()
        
        # Encoder
        self.encoder = nn.Sequential(
            nn.Linear(input_dim, 32),
            nn.BatchNorm1d(32),
            nn.LeakyReLU(0.2),
            nn.Linear(32, 16),
            nn.BatchNorm1d(16),
            nn.LeakyReLU(0.2),
            nn.Linear(16, latent_dim)
        )
        
        # Decoder
        self.decoder = nn.Sequential(
            nn.Linear(latent_dim, 16),
            nn.BatchNorm1d(16),
            nn.LeakyReLU(0.2),
            nn.Linear(16, 32),
            nn.BatchNorm1d(32),
            nn.LeakyReLU(0.2),
            nn.Linear(32, input_dim)
        )

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        latent = self.encoder(x)
        reconstructed = self.decoder(latent)
        return reconstructed, latent

    def compute_anomaly_score(self, x: torch.Tensor) -> torch.Tensor:
        """Computes sample-wise MSE reconstruction error."""
        with torch.no_grad():
            reconstructed, _ = self.forward(x)
            mse = torch.mean((x - reconstructed) ** 2, dim=1)
            return mse
