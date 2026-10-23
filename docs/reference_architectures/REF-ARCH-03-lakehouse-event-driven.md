# 🗄️ Reference Architecture 03: Petabyte-Scale Lakehouse & Event-Driven Outbox

> **Target Audience**: Principal Data Engineers, Chief Data Officers, Distributed Systems Architects.

---

## 1. Executive Summary
This reference architecture provides a unified data platform and event-driven microservices blueprint for smart manufacturing. It combines **Apache Iceberg / Delta Lakehouse** storage with a **Transactional Outbox Pattern**, a **Feast-compatible dual feature store**, and **Distributed Saga Orchestration** to achieve sub-second streaming ingestion, point-in-time correctness, and backward-compensating rollbacks across distributed plant systems.

---

## 2. Architecture Diagram & Event Topography
```mermaid
flowchart TD
    subgraph IngestionTier["🏭 Edge Stream Ingestion"]
        SENSORS["Vibration / Temp / Acoustic Streams"]
        KAFKA["Apache Kafka Broker Cluster"]
    end

    subgraph DualStore["⚡ Dual-Path Processing Engine"]
        SPARK_STREAM["Spark Structured Streaming (<1s Batches)"]
        SPARK_BATCH["Batch Spark / Dataproc (Hourly Compaction)"]
    end

    subgraph LakehouseTier["🧊 Apache Iceberg / Delta Lakehouse"]
        ICEBERG_METADATA["Iceberg Snapshots & Manifests (S3/GCS)"]
        PARQUET_DATA["Snappy Columnar Parquet Partitions"]
        TIME_TRAVEL["Time-Travel Engine (as_of_snapshot / timestamp)"]
    end

    subgraph FeatureStoreTier["📊 Feast-Compatible Feature Store"]
        ONLINE_FS["Online Store: Redis 7.2 (Sub-2ms Lookup)"]
        OFFLINE_FS["Offline Store: Parquet Historical Join"]
        FRESHNESS["Freshness SLA Auditor (<60s Streaming SLA)"]
    end

    subgraph MicroservicesTier["⚙️ Microservices & Resiliency Patterns"]
        OUTBOX["Transactional Outbox (Exactly-Once Semantics)"]
        IDEMPOTENCY["Idempotency Key Manager (24h TTL)"]
        SAGA["CQRS Saga Orchestrator (Rollback Compensation)"]
    end

    SENSORS --> KAFKA
    KAFKA --> SPARK_STREAM & SPARK_BATCH
    SPARK_STREAM --> ONLINE_FS & ICEBERG_METADATA
    SPARK_BATCH --> PARQUET_DATA --> ICEBERG_METADATA

    ONLINE_FS --> FRESHNESS
    ICEBERG_METADATA --> TIME_TRAVEL --> OFFLINE_FS

    KAFKA <--> OUTBOX
    OUTBOX --> IDEMPOTENCY --> SAGA
```

---

## 3. Data Freshness SLAs & Feature Engineering Profile
| Pipeline Path | Data Modality | Freshness SLA | Processing Engine | Storage Target |
| :--- | :--- | :--- | :--- | :--- |
| **Streaming Hot Path** | Vibration RMS, Spindle RPM, Bearing Temp | **$<60\text{ seconds}$** | Kafka + Micro-batches | Redis 7.2 Online Feature Store |
| **Batch Historical Path** | 24-hr Aggregate Statistics, Tool Wear Indices | **$<24\text{ hours}$** | PySpark / Dataproc Serverless | Apache Iceberg / Delta Lakehouse |
| **Vision Defect Archive** | Stamped Casings Raw Imagery (10GbE) | **$<5\text{ minutes}$** | MinIO Multipart Upload | S3/GCS Coldline Storage Tier |

---

## 4. Saga Orchestration Failure Mode Case Study
When an imminent spindle failure is detected:
1. **Forward Path**: Anomaly Flagged $\to$ Inventory Reserved $\to$ Work Order Dispatched $\to$ Line Throttled.
2. **Failure Injection**: ERP throws `INSUFFICIENT_STOCK_ERROR` on bearing part `SKF-6205`.
3. **Compensating Rollback**: The Saga Orchestrator catches the exception, cancels the incomplete work order, releases inventory holds, and escalates an urgent procurement alarm to the plant floor supervisor without leaving dirty state.
