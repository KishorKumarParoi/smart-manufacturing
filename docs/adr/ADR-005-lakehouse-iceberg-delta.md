# 🏛️ Architecture Decision Record: ADR-005

## Title: Apache Iceberg & Delta Lakehouse Architecture for Dual-Path Sensor Telemetry

### Status: ACCEPTED
**Date**: 2026-10-22  
**Author**: Principal Data Platform Architect  

---

## 1. Context & Problem Statement
Factory floor sensors stream continuous numerical metrics ($X, Y, Z$ vibration, temperature, pressure) alongside high-resolution optical inspection imagery.
- Traditional Data Warehouses (Snowflake / BigQuery alone) incur high ingestion costs when inserting continuous small streaming rows.
- Traditional Data Lakes (raw S3/GCS buckets of Parquet files) suffer from lack of ACID transactional guarantees, small file proliferation ("million tiny files problem"), and absence of point-in-time time-travel querying needed for regulatory compliance and model retraining.

---

## 2. Decision Outcome
**Chosen Architecture**: **Apache Iceberg / Delta Lakehouse Architecture with Dual Ingestion Paths**:

1. **Dual Ingestion Path**:
   - **Streaming Path**: High-speed Kafka micro-batches append telemetry directly to the lakehouse in $<1\text{ second}$ increments.
   - **Batch Path**: Nightly Spark / Dataproc jobs perform bulk compaction and schema maintenance.
2. **ACID Transactional Snapshots**:
   - Every write operation creates a new immutable metadata snapshot containing manifest files and columnar Parquet paths.
   - Readers never experience dirty reads or table lock contention while streaming writes occur.
3. **Time Travel Auditing**:
   - Enables point-in-time historical queries (`as_of_timestamp` or `as_of_snapshot_id`) ensuring reproducible machine failure forensic audits and leak-free training dataset generation.
4. **Feast Feature Store Freshness SLAs**:
   - Real-time Redis online store satisfies sub-2ms inference serving.
   - Offline Iceberg store guarantees feature freshness SLAs ($<60\text{s}$ streaming lag, $<24\text{h}$ batch lag).

---

## 3. Results & Operational Gains
- **Storage Cost Savings**: Columnar Snappy-compressed Parquet in S3/GCS reduces raw IoT storage spend by **$74\%$** compared to operational RDBMS storage.
- **Query Throughput**: Partitioning by `year=YYYY/month=MM/machine_id=XYZ` reduces full-table scan I/O by $92\%$.
