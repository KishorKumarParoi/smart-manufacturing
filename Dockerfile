# Production Dockerfile for Smart Manufacturing MLOps Platform
FROM python:3.11-slim

WORKDIR /app

# Install minimal runtime dependencies (curl for healthchecks)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast dependency resolution
RUN pip install --no-cache-dir uv

# Copy dependency files first (Docker layer cache)
COPY pyproject.toml requirements.txt* ./

# Install all project dependencies from requirements.txt via uv
RUN uv pip install --system --no-cache -r requirements.txt

# Copy full application source including pre-trained model artifacts
COPY . /app

# Ensure model artifacts directory exists (non-fatal if pkl files are absent)
RUN mkdir -p artifacts/models artifacts/processed

# Standard port for container and Kubernetes manifests
EXPOSE 5000

# Environment configuration
ENV PORT=5000 \
    FLASK_APP=application.py \
    PYTHONPATH=/app \
    PYTHONUNBUFFERED=1

# Container health check probe
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=5 \
  CMD curl -f http://localhost:5000/api/health || exit 1

# Launch application server
CMD ["python", "application.py"]