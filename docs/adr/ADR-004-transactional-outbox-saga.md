# 🏛️ Architecture Decision Record: ADR-004

## Title: Transactional Outbox & Distributed Saga Orchestration over Two-Phase Commit (2PC)

### Status: ACCEPTED
**Date**: 2026-10-21  
**Author**: Principal Distributed Systems Architect  

---

## 1. Context & Problem Statement
When a critical mechanical anomaly or optical defect occurs, the platform must execute a distributed sequence of actions across heterogeneous systems:
1. State mutation: Flag machine anomaly in local database.
2. ERP Inventory: Reserve replacement spindle bearing (`SKF-6205`).
3. Maintenance System: Generate technician work order.
4. Physical Line Control: Throttle machine spindle RPM.

In distributed microservices, using **Two-Phase Commit (2PC)** or distributed locking (e.g. XA transactions) causes severe architectural liabilities:
- Synchronous blocking locks reduce system availability to the product of all participating services ($A_{total} = A_1 \times A_2 \times A_3 \times A_4$).
- Network latency or slow ERP responses stall the database, holding row locks and causing cascading connection pool exhaustion.

---

## 2. Decision Outcome
**Chosen Architecture**: **Transactional Outbox Pattern + Asynchronous CQRS Saga Orchestration**:

### 1. Transactional Outbox with Exactly-Once Delivery:
- State mutations and event records are written to a single local transactional envelope.
- An asynchronous background poller publishes outbox events to Kafka / EventBridge.
- Cryptographic idempotency keys (`idempotency_key = sha256(aggregate + action + timestamp)`) ensure duplicate incoming messages are discarded safely without duplicate side effects.
- Exponential backoff retries with Dead-Letter Queue (DLQ) escalation.

### 2. Distributed Saga Orchestrator:
- Implements a backward-compensating workflow:
  $$\text{Execute: } S_1 \to S_2 \to S_3 \to S_4$$
  $$\text{If } S_3 \text{ fails: } C_2 \to C_1 \text{ (Rollback)}$$
- If the ERP inventory service is unavailable, the Saga automatically triggers compensating actions in reverse order (`LIFO`), releasing uncommitted reservations and alerting the shift manager.

---

## 3. Trade-off Analysis
- **Consistency Model**: Eventual consistency is accepted in exchange for $99.99\%$ operational availability.
- **Latency**: Decouples physical machine telemetry from slow ERP inventory networks ($<15\text{ms}$ local response vs $>800\text{ms}$ 2PC lock wait).
