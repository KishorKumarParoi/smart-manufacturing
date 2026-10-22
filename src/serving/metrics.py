from prometheus_client import Counter, Histogram, Gauge, REGISTRY


def _get_or_create(metric_cls, name, documentation, *args, **kwargs):
    if name in REGISTRY._names_to_collectors:
        return REGISTRY._names_to_collectors[name]
    try:
        return metric_cls(name, documentation, *args, **kwargs)
    except Exception:
        return REGISTRY._names_to_collectors.get(name)


# Prometheus metric collectors
INFERENCE_REQUESTS_TOTAL = _get_or_create(
    Counter,
    "smart_mfg_inference_requests_total",
    "Total inference requests handled",
    ["model_type", "cloud_provider", "region", "status"],
)

INFERENCE_LATENCY_SECONDS = _get_or_create(
    Histogram,
    "smart_mfg_inference_latency_seconds",
    "Inference execution latency in seconds",
    ["model_type", "device"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5),
)

ANOMALIES_DETECTED_TOTAL = _get_or_create(
    Counter,
    "smart_mfg_anomalies_detected_total",
    "Total machine anomalies and defective parts flagged",
    ["severity", "machine_id"],
)

GPU_MEMORY_ALLOCATED_MB = _get_or_create(
    Gauge,
    "smart_mfg_gpu_memory_allocated_mb",
    "GPU memory currently allocated by inference engine in Megabytes",
)

CLOUD_CLUSTER_HEALTH = _get_or_create(
    Gauge,
    "smart_mfg_cloud_cluster_health",
    "Health status of current cloud cluster (1 = healthy, 0 = degraded)",
    ["cloud_provider", "region"],
)

