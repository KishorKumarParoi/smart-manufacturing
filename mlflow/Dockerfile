FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    mlflow==2.17.0 \
    psycopg2-binary==2.9.9 \
    boto3==1.35.32 \
    google-cloud-storage==2.18.2

EXPOSE 5000

ENV BACKEND_STORE_URI="sqlite:////mlflow/mlflow.db"
ENV ARTIFACT_ROOT="s3://smart-mfg-mlops-artifacts-us-east-1/mlflow"

CMD ["sh", "-c", "mlflow server --host 0.0.0.0 --port 5000 --backend-store-uri ${BACKEND_STORE_URI} --default-artifact-root ${ARTIFACT_ROOT}"]
