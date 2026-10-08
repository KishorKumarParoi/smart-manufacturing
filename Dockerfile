# Production Dockerfile for Smart Manufacturing MLOps Platform
FROM python:3.11-slim

WORKDIR /app

# Install minimal runtime dependencies (curl for healthchecks)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Cache Python dependencies in separate layer
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application source code and pre-trained artifacts
COPY . /app

# Standard port for container and Kubernetes manifests
EXPOSE 5000

# Environment configuration
ENV PORT=5000 \
    FLASK_APP=application.py \
    PYTHONPATH=/app \
    PYTHONUNBUFFERED=1

# Container health check probe
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:5000/api/health || exit 1

# Launch application server
CMD ["python", "application.py"]