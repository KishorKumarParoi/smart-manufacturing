# 🔍 Reference Architecture 02: Real-Time Industrial Hybrid RAG & Autonomous Copilot with Policy Guardrails

> **Target Audience**: Principal AI Engineers, Enterprise LLMOps Architects, Security Directors.

---

## 1. Executive Summary
This reference architecture provides an end-to-end blueprint for a **defense-in-depth Industrial GenAI Copilot**. It combines NVIDIA NeMo-style policy guardrails, reversible PII tokenization vaults, OWASP LLM01 injection defense, hybrid vector/lexical retrieval, local ONNX cross-encoder re-ranking, and G-Eval style evaluation harnesses.

---

## 2. Architectural Topology & Sequence Flow
```mermaid
sequenceDiagram
    autonumber
    actor Tech as Plant Technician
    participant Cockpit as Next.js 15 Cockpit
    participant Guard as Policy Guardrail Engine
    participant PII as PII Token Vault
    participant Cache as Semantic Cache (<50ms)
    participant Hybrid as Hybrid Retriever (Dense + BM25)
    participant Rerank as FlashRank Cross-Encoder
    participant LLM as Industrial LLM Core
    participant GEval as G-Eval Evaluation Harness
    participant Audit as Cryptographic Audit Trail

    Tech->>Cockpit: Submits Maintenance Query
    Cockpit->>Guard: POST /api/v1/rag/query
    Guard->>Guard: Inspect for Prompt Injection (OWASP LLM01)
    Guard->>PII: Redact Emails, Employee IDs, IPs into Token Vault
    Guard->>Guard: Verify Industrial Domain Topic Gating

    alt Query In Cache
        Guard->>Cache: SHA-256 Key Probe
        Cache-->>Cockpit: Sub-5ms Cached Response + Citations
    else Cache Miss
        Guard->>Hybrid: Execute Parallel Dense + BM25 Search
        Hybrid->>Hybrid: Reciprocal Rank Fusion (k=60)
        Hybrid->>Rerank: Top 10 Candidate Chunks
        Rerank->>Rerank: Cross-Attention Scoring & Re-ranking
        Rerank->>LLM: Augmented Prompt + Top 2 SOP Chunks
        LLM-->>Guard: Synthesized Operational Guidance
        Guard->>Guard: Validate Output Safety (No bypass recommendations)
        Guard->>GEval: Score Faithfulness & Relevance
        Guard->>Audit: Append Block to Hash-Chained Ledger
        Guard->>Cache: Commit Response to In-Memory Cache
        Guard-->>Cockpit: HTTP 200 (Guidance + Citations + G-Eval Score)
    end
```

---

## 3. End-to-End Latency Budget & SLA Profile
| Layer / Operation | Target Budget | Measured P50 | Measured P95 | Fallback Mechanism |
| :--- | :--- | :--- | :--- | :--- |
| **Edge Guardrail & PII** | $<5\text{ms}$ | $0.8\text{ms}$ | $1.8\text{ms}$ | Fail-closed on injection; pass-through on benign |
| **Semantic Cache Hit** | $<10\text{ms}$ | $0.2\text{ms}$ | $0.5\text{ms}$ | Fallback to retrieval on cache miss |
| **Hybrid Search + BM25** | $<20\text{ms}$ | $4.2\text{ms}$ | $8.5\text{ms}$ | Degrade to pure BM25 if vector search times out |
| **FlashRank Re-ranking** | $<35\text{ms}$ | $12.1\text{ms}$ | $24.0\text{ms}$ | Return RRF fused order without reranking |
| **LLM Inference** | $<800\text{ms}$ | $350.0\text{ms}$ | $750.0\text{ms}$ | Secondary LLM provider circuit breaker |
| **Total Cold Request** | **$<1,000\text{ms}$** | **$367.7\text{ms}$** | **$785.7\text{ms}$** | SLA compliant |

---

## 4. Security & Guardrails Matrix
- **Prompt Injection Defense**: Intercepts instruction overrides, delimiter attacks, base64 payloads, and system prompt leakage before reaching vector search or LLM context.
- **PII Anonymization**: Reversibly replaces sensitive identities (`<REDACTED_EMAIL_1>`, `<REDACTED_EMPLOYEE_ID_1>`), restoring them only in authorized operator displays.
- **Output Safety Guardrail**: Intercepts any generated instruction recommending physical safety bypasses, relief valve tampering, or operating above rated machine RPM.
