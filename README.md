# MedComplyAI — Architecture and Deployment Documentation

> **AI-native regulatory compliance platform for medical devices and pharmaceuticals, built entirely on local, open-weight models.**

**Status:** Source closed. Deployed on-premise with paying users. This repository
is published as architecture and deployment reference. It contains no application
source.

The deployment topology in [`reference/`](reference/) is real and runnable. Qdrant
and Ollama start for anyone. The backend and frontend pull private images and need
registry access. See [Deployment](#deployment).

MedComplyAI turns a pile of regulatory documents (MDR, 510(k), ISO 14971, ISO 13485, CTD modules, drug labeling, IFUs) into a living, auditable compliance intelligence system. No cloud LLM APIs. No data leaves your environment. Every AI output is grounded, cited, and revision-tracked.

---

## Table of Contents

- [Why This System](#why-this-system)
- [Feature Overview](#feature-overview)
- [Architecture](#architecture)
  - [High-Level Diagram](#high-level-diagram)
  - [Ingestion Pipeline](#ingestion-pipeline)
  - [Retrieval Stack](#retrieval-stack)
  - [Gap Analysis Engine](#gap-analysis-engine)
  - [Glass Box AI Layer](#glass-box-ai-layer)
  - [Intelligence & Co-Pilot](#intelligence--co-pilot)
  - [Portfolio & Program Layer](#portfolio--program-layer)
- [Tech Stack](#tech-stack)
- [Directory Structure](#directory-structure)
- [Deployment](#deployment)
  - [Host requirements](#host-requirements)
  - [Ports](#ports)
  - [Start the stack](#start-the-stack)
  - [Pull the models](#pull-the-models)
  - [Overlays](#overlays)
- [Configuration](#configuration)
- [API Reference](#api-reference)
- [Data Privacy & Security](#data-privacy--security)
- [Roadmap](#roadmap)

---

## Why This System

*A note from a systems builder.*

Most regulatory compliance tooling sits in one of two camps:

1. **Static checklists** — spreadsheets and PDFs that require a human expert to manually cross-reference every requirement against every document. Correct, but brutally slow. Doesn't scale across products or regulatory regions.

2. **Cloud-hosted AI summarizers** — LLM wrappers that ingest documents and answer questions. Fast, but fundamentally unauditable: the model hallucinates, citations are made up, and you cannot explain *why* a requirement is "met" in a way that would survive an FDA inspection.

MedComplyAI is built around a third model: **deterministic, evidence-indexed AI**.

### The core insight

Regulators don't care what an LLM thinks. They care about *evidence artifacts*: specific text in specific document sections, with a traceable rationale for why that text satisfies a specific clause.

So the system is designed from the evidence up:

- **Chunking is structural**, not arbitrary. Documents are split at section boundaries with hierarchy preserved (section path, section number, semantic label). Every chunk knows what it is.
- **Coverage decisions are deterministic.** For ISO 14971 and MDR Annex I, the coverage decision is made by deterministic keyword classifiers that mirror how a human auditor reads the document. Those two evaluators contain no LLM calls at all, and no LLM writes a status, verdict, or coverage field anywhere in the system. LLMs are called only to explain or narrate. The scope matters: other frameworks route through a schema-agnostic path where the model does propose a finding severity, which is why this claim names ISO 14971 and MDR Annex I specifically rather than the whole product.
- **Every AI output is grounded-validated before it reaches the user.** The LLM Gateway enforces a grounding contract: the model must cite evidence IDs that actually exist in the retrieved context. Ungrounded outputs are blocked, not just flagged.
- **All state is append-only snapshots.** A compliance run produces a versioned, hash-stamped snapshot: the payload is canonically serialised and SHA-256 hashed, and that hash binds every downstream LLM interaction to the exact engine state it was generated from. Snapshots can be compared across runs and exported as an audit bundle. There is a single write path and no update or delete, so nothing rewrites what the system decided and why. Two honest limits: the stored hash is a provenance stamp, not a tamper check, because nothing recomputes and compares it yet; and snapshot replay is not implemented.

### Why local models?

Pharmaceutical and medical device companies operate under 21 CFR Part 11, GDPR, and internal data governance policies that make it difficult or impossible to send patient-adjacent or IP-adjacent documents to third-party cloud APIs. Running Qwen 2.5 7B on-premise via Ollama gives you:

- Full data sovereignty
- Reproducible outputs (pinned model version)
- No per-token cost at inference time
- Offline operation in air-gapped environments

The quality tradeoff is real — a 7B parameter model is not GPT-4 — but it is surprisingly capable for structured extraction and summarization tasks when the retrieval context is well-constructed. The system compensates with retrieval quality, not model scale.

### Why not just use a vector database + RAG?

Standard RAG is fine for question answering. It falls apart for compliance because:

1. **Requirements are multi-hop.** "ISO 14971 TRACEABILITY" is only met if you have hazard identification *and* risk control *and* verification all present in the same Risk Management File. A single similarity search against an embedding index cannot verify structural completeness.

2. **Absence matters.** If a document doesn't mention residual risk evaluation, that's a critical finding — not just a low-similarity result. The system needs to distinguish "not found" from "searched and absent" from "not assessed."

3. **Evidence taxonomy is domain-specific.** "Risk" is mentioned in every pharmaceutical document. It means something very different in an ISO 14971 context vs. a business risk context. The evaluators encode this domain knowledge explicitly.

4. **Auditability requires provenance.** Every coverage decision needs to be explainable as: "We searched N candidates from these sections; here are the top K; here's why chunk X was classified as strong evidence; here's the threshold rule we applied."

The gap engine builds all of this on top of the vector database, not instead of it.

---

## Feature Overview

| Capability | Description |
|---|---|
| **Document Ingestion** | PDF, DOCX upload with hierarchical section parsing, semantic labeling, and Qdrant vector indexing |
| **Regulatory Q&A** | RAG-powered chat with hybrid retrieval (dense + sparse + metadata filtering) |
| **Basic Gap Analysis** | Section-level LLM gap detection between any two documents |
| **Advanced Gap Analysis** | Multi-framework compliance checks: MDR, ISO 14971, ISO 13485, CTD, 510(k), Drug Labeling, Device IFU |
| **Submission Readiness Score** | Weighted readiness metric from gap findings with blocker detection |
| **Glass Box Copilot** | Grounded query-to-snapshot AI that can only cite evidence that exists |
| **Evidence Explanations** | Per-requirement narrative explanations with span-level citations |
| **Document Draft Studio** | Template-based regulatory document drafting (SmPC, IFU, CTD sections) |
| **Review Queue** | Human-in-the-loop review workflow for AI-proposed outputs |
| **Portfolio Analytics** | Cross-product run comparison, trend timelines, compliance hotspot detection |
| **Program Risk Intelligence** | Cross-product requirement failure clustering and root cause analysis |
| **Change Impact Analysis** | What-if impact of a document change on downstream compliance requirements |
| **Submission Gates** | Configurable readiness gates with pass/fail/conditional logic |
| **Scenario Simulation** | Simulate how adding/removing evidence chunks shifts the readiness score |
| **Policy Packs** | Pluggable compliance packs (EU MDR, FDA 510k, ISO 14971, etc.) |
| **Org Governance** | Tenant-level configuration for approved frameworks and access control |
| **Observability** | Optional Langfuse integration for LLM tracing and prompt analytics |

---

## Architecture

### High-Level Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MedComplyAI                                     │
├──────────────────────────────────────────────────────────────────┬──────────┤
│                         Next.js Frontend                         │          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────┐ │          │
│  │  Gap     │ │ Portfolio│ │ Copilot  │ │  Draft   │ │ Gates │ │          │
│  │ Analysis │ │ Analytics│ │  Chat    │ │  Studio  │ │       │ │          │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └───────┘ │          │
├──────────────────────────────────────────────────────────────────┤  Ollama  │
│                        FastAPI Backend                           │          │
│  ┌─────────────────────────────────────────────────────────────┐ │  Qwen2.5 │
│  │                    Intelligence Layer                        │ │   7B     │
│  │  Glass Box AI  │  LLM Gateway  │  Grounding Validator       │ │          │
│  └─────────────────────────────────────────────────────────────┘ │  GTE-    │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────────┐ │  Qwen2   │
│  │ Gap Engine │ │  Copilot   │ │ Portfolio  │ │   Program    │ │  1.5B    │
│  │            │ │ Orchestr.  │ │  Service   │ │ Intelligence │ │  Embed   │
│  └────────────┘ └────────────┘ └────────────┘ └──────────────┘ │          │
│  ┌─────────────────────────────────────────────────────────────┐ ├──────────┤
│  │                     Retrieval Stack                          │ │          │
│  │  Qdrant Client  │  Hybrid Reranker  │  Cache Service        │ │  Qdrant  │
│  └─────────────────────────────────────────────────────────────┘ │          │
│  ┌─────────────────────────────────────────────────────────────┐ │  Vector  │
│  │                    Ingestion Pipeline                        │ │   DB     │
│  │  PDF Parser  │  DOCX Parser  │  Hierarchical Chunker        │ │          │
│  │  Semantic Labeler  │  Embedding Service  │  Qdrant Indexer  │ │          │
│  └─────────────────────────────────────────────────────────────┘ ├──────────┤
│  ┌─────────────────────────────────────────────────────────────┐ │          │
│  │                  Persistence Layer                           │ │  SQLite  │
│  │  GapRunDB  │  SnapshotDB  │  ReviewQueueDB  │  GovernanceDB │ │          │
│  └─────────────────────────────────────────────────────────────┘ │          │
└──────────────────────────────────────────────────────────────────┴──────────┘
```

### Ingestion Pipeline

```
Upload (PDF/DOCX)
       │
       ▼
┌─────────────┐
│  File Parser │   pdfplumber (text layer) + Qwen VL (scanned pages)
│             │   python-docx (structured DOCX)
└──────┬──────┘
       │  raw sections with titles, page spans, text
       ▼
┌─────────────────────┐
│  Hierarchical        │   Builds section tree from heading styles / numbering
│  Section Detector   │   Assigns section_path: ["4", "4.2", "4.2.1"]
└──────┬──────────────┘
       │
       ▼
┌──────────────────┐
│  Semantic Labeler │   Rule + LLM assigns semantic_label:
│                  │   indications / dosage / warnings / contraindications /
│                  │   adverse_reactions / ifu_required_content / etc.
└──────┬───────────┘
       │
       ▼
┌────────────────────┐
│  Hierarchical       │   Chunks within section boundaries. Parent ~3000 chars
│                    │   (max 4500), child max 1200, parent_text carried on
│                    │   each child for retrieval context
│  Chunker           │   Preserves lists, tables as single chunks
│                    │   Assigns: chunk_type (BODY/TABLE/HEADER_ONLY), chunk_index
└──────┬─────────────┘
       │
       ▼
┌────────────────┐
│  Embedding     │   GTE-Qwen2 1.5B (local via Ollama)
│  Service       │   1536-dim dense vectors
└──────┬─────────┘
       │
       ▼
┌────────────────┐
│  Qdrant Index  │   Payload: text, doc_id, product_name, region, authority,
│                │   role, product_type, semantic_label, section_path,
│                │   chunk_type, device_risk_class, page_span, ...
└────────────────┘
```

### Retrieval Stack

```
Query
  │
  ├─ Rule-based Query Interpreter
  │    ├─ Classify: FREE_TEXT / METADATA_SPECIFIC / COMPARATIVE / STRUCTURAL / REGULATORY_TASK
  │    └─ Extract: region / authority / role / product_type / semantic_label / device_class
  │
  ├─ Dense Retrieval (Qdrant cosine similarity)
  │    └─ Metadata-filtered payload search
  │
  ├─ Sparse Retrieval (BM25 over Qdrant payload text)
  │
  └─ Hybrid Reranker
       ├─ Vector weight:   0.70
       ├─ Metadata weight: 0.20
       └─ Recency weight:  0.10
            │
            └─ Top-K ranked candidates → context assembly
```

### Gap Analysis Engine

The gap engine has two tiers:

**Basic Gap** — LLM-driven section pair comparison
```
Standard Doc  ──┐
                ├─ Section Alignment (embedding cosine + BM25 lexical)
Test Doc      ──┘         │
                    Aligned pairs
                          │
                    Batch LLM pass (3 pairs/batch, Qwen 7B)
                          │
                    Gap findings per category:
                    [missing_content / unclear_language / inconsistent_content /
                     non_compliant / formatting_issue]
                          │
                    Critic pass (optional, validates/prunes findings)
                          │
                    Persisted GapRun + Snapshot
```

**Advanced Gap** — deterministic framework evaluators + LLM for labeling
```
┌──────────────────────────────────────────────────┐
│  Framework Dispatchers                           │
│                                                  │
│  MDR GSPR (Annex I)   → mdr_gap_service          │
│  ISO 14971            → iso14971_evaluator        │
│  ISO 13485            → iso13485_evaluator        │
│  FDA 510(k)           → iso_gap_service           │
│  CTD Module           → ctd_gap_service           │
│  Drug Labeling (SmPC) → drug_label_llm_evaluator  │
│  Device IFU           → device_ifu_gap_service    │
└─────────────────┬────────────────────────────────┘
                  │
                  ▼
    For each requirement definition in framework:
      1. Fetch candidate chunks from Qdrant (top_k × 3)
      2. Rank by keyword score + chunk_type bonus + embedding sim
      3. Classify each candidate: strong / weak / none
         (deterministic rules — no LLM)
      4. Apply threshold:
         met      = ≥1 strong  OR  ≥2 weak (with RM context)
         partial  = ≥1 weak
         not_met  = 0 evidence, candidates exist
         not_assessed = 0 candidates
      5. Build CoverageItem with evidence spans + search trail
         (absence trail = what was searched but not found)
      6. Compute ReadinessScore from weighted CoverageItems
```

### Glass Box AI Layer

The Glass Box layer is the safety harness around all LLM calls in the intelligence features:

```
User query
    │
    ▼
Query Router  →  STATUS / LIST / SUMMARY / COMPARE / EXPLANATION
    │
    ▼ (EXPLANATION / UNKNOWN only)
Context Assembler
    ├─ Load snapshot from DB
    ├─ Fetch coverage items, blockers, framework scores
    └─ Build evidence_spans index (span_id → chunk text)
    │
    ▼
LLM Gateway
    ├─ Build structured prompt: "Answer ONLY using evidence IDs: [E1, E2, ...]"
    ├─ Call Ollama (Qwen 7B, temperature 0.1)
    └─ Parse structured output
    │
    ▼
Grounding Validator (v2.3)
    ├─ Extract all span references from LLM output
    ├─ Verify each referenced span exists in evidence_spans index
    ├─ Check no fabricated IDs
    └─ Block output if grounding fails
    │
    ▼ (grounded)
CopilotResponse
    ├─ answer: string
    ├─ citations: [{run_id, span_id, section_title, quote}]
    └─ grounded_claims: [{claim_text, field_references}]
```

STATUS, LIST, SUMMARY, and COMPARE queries bypass the LLM entirely — they are answered from deterministic snapshot data.

### Intelligence & Co-Pilot

The intelligence layer provides four capabilities on top of the Glass Box foundation:

```
┌─────────────────────────────────────────────────────────┐
│                  Intelligence Layer                      │
├─────────────────┬────────────────┬───────────┬──────────┤
│ Evidence        │ Query Copilot  │  Draft    │  Review  │
│ Explanation     │                │  Studio   │  Queue   │
├─────────────────┼────────────────┼───────────┼──────────┤
│ Per-requirement │ Natural lang.  │ Template  │ HITL for │
│ narrative why   │ queries over   │ -based    │ proposed │
│ evidence met/   │ snapshot data  │ doc gen   │ outputs  │
│ didn't meet     │ Grounded-only  │ SmPC/IFU/ │ confirm/ │
│ requirement     │ answers        │ CTD/risk  │ override │
└─────────────────┴────────────────┴───────────┴──────────┘
```

The Co-Pilot also exposes a multi-step agentic layer (`CoPilotWorkflow`):

- `LABEL_UPDATE` — identifies required changes from CCDS delta to SmPC/PI
- `REG_STRATEGY` — drafts regional regulatory strategy from product metadata
- `CONSISTENCY_CHECK` — cross-label harmonization verification
- `SUBMISSION_CHECK` — pre-submission readiness walk-through

### Portfolio & Program Layer

```
Multiple Products / Multiple Runs
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│  Portfolio Service                                          │
│  ├─ Run-to-run delta comparison (DeltaType enum)            │
│  ├─ Product timeline (readiness trend over time)            │
│  └─ Requirement stability heatmap                           │
└─────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│  Program Intelligence Service                               │
│  ├─ Cross-product risk register (which reqs fail most?)     │
│  ├─ Root cause clustering (shared document gap?)            │
│  └─ Remediation playbooks (standard fix patterns)           │
└─────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│  Change Impact Analysis                                      │
│  └─ Given a proposed change to document X, simulate which   │
│     requirements shift status and by how much               │
└─────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

### Backend
| Component | Technology |
|---|---|
| API Framework | FastAPI + Uvicorn |
| ORM / DB | SQLAlchemy + SQLite (aiosqlite) |
| Vector DB | Qdrant |
| LLM Inference | Ollama (local) |
| Embedding | GTE-Qwen2 1.5B via Ollama |
| RAG Primary | LangChain LCEL |
| RAG Fallback | LlamaIndex |
| Workflow Orchestration | LangGraph |
| Prompt Optimization | DSPy (experimental) |
| Observability | Langfuse (optional) |
| PDF Parsing | pdfplumber + pdf2image |
| DOCX Parsing | python-docx |
| Sparse Retrieval | rank_bm25 |
| Validation | Pydantic v2 |

### Frontend
| Component | Technology |
|---|---|
| Framework | Next.js 13 (App Router) |
| UI | React 18 + TypeScript |
| Styling | Tailwind CSS |
| Icons | Lucide React + Heroicons |
| Markdown | react-markdown |
| HTTP | Axios |

### Infrastructure
| Component | Technology |
|---|---|
| Containerization | Docker + Docker Compose |
| LLM Server | Ollama |
| Vector Database | Qdrant |
| LLM Observability | Langfuse (optional profile) |

---

## Directory Structure

```
MedComplyAI/
├── backend/
│   ├── app/
│   │   ├── main.py                    # FastAPI app factory
│   │   ├── config.py                  # All settings (pydantic-settings)
│   │   ├── database.py                # SQLAlchemy models + session
│   │   │
│   │   ├── api/                       # Route handlers
│   │   │   ├── routes_gap.py          # Gap analysis endpoints
│   │   │   ├── routes_intelligence.py # Glass Box AI endpoints
│   │   │   ├── routes_copilot.py      # Co-pilot endpoints
│   │   │   ├── routes_portfolio.py    # Portfolio analytics
│   │   │   ├── routes_program.py      # Program intelligence
│   │   │   ├── routes_impact.py       # Change impact analysis
│   │   │   ├── routes_gates.py        # Submission gates
│   │   │   ├── routes_scenarios.py    # Scenario simulation
│   │   │   ├── routes_documents.py    # Document management
│   │   │   ├── routes_ingestion.py    # Document ingestion
│   │   │   ├── routes_chat.py         # RAG chat
│   │   │   ├── routes_regulatory.py   # Regulatory query
│   │   │   └── ...
│   │   │
│   │   ├── gap/                       # Core gap evaluators
│   │   │   ├── iso14971_evaluator.py  # ISO 14971 deterministic rules
│   │   │   ├── mdr_ifu_coverage.py    # MDR Annex I evaluator
│   │   │   ├── status_policy.py       # met/partial/not_met thresholds
│   │   │   ├── verification_hash.py   # Snapshot integrity hashing
│   │   │   └── verification_service.py
│   │   │
│   │   ├── intelligence/              # Glass Box AI
│   │   │   ├── copilot_service.py     # Copilot query handler
│   │   │   ├── context_assembly.py    # Snapshot → prompt context
│   │   │   ├── grounding_validator.py # LLM output grounding check
│   │   │   ├── llm_gateway.py         # Structured LLM calls
│   │   │   ├── query_router.py        # Query type classification
│   │   │   ├── draft_service.py       # Template-based drafting
│   │   │   ├── review_service.py      # Review queue management
│   │   │   ├── evidence_explainer.py  # Per-evidence narratives
│   │   │   └── prompts/               # Prompt templates
│   │   │
│   │   ├── portfolio/                 # Portfolio analytics
│   │   ├── program/                   # Program risk intelligence
│   │   ├── impact/                    # Change impact analysis
│   │   ├── gates/                     # Submission gates
│   │   ├── scenarios/                 # Scenario simulation
│   │   ├── policy/                    # Policy pack registry
│   │   ├── governance/                # Org governance
│   │   │
│   │   ├── services/
│   │   │   ├── gap_run_service.py          # Run queue + worker loop
│   │   │   ├── regulatory_query_service.py # Query interpretation
│   │   │   ├── hierarchical_chunking_service.py
│   │   │   ├── chunking_service.py
│   │   │   ├── evaluation_service.py
│   │   │   ├── rag/                        # RAG orchestration
│   │   │   ├── retrieval/                  # Hybrid retrieval
│   │   │   ├── workflows/                  # LangGraph workflows
│   │   │   ├── copilot/                    # Co-pilot workflows
│   │   │   ├── observability/              # Langfuse tracer
│   │   │   └── optimization/               # DSPy optimizer
│   │   │
│   │   ├── models/
│   │   │   └── schemas.py             # All Pydantic schemas
│   │   │
│   │   └── clients/
│   │       └── ollama_client.py       # Async Ollama HTTP client
│   │
│   ├── requirements.txt
│   └── storage/                       # Runtime data (gitignored)
│       ├── documents/                 # Uploaded files
│       ├── gap_documents/             # Gap run documents
│       ├── gap_runs/                  # Checkpoint JSONs
│       └── regulatory/parsed/        # Parsed regulation artifacts
│
├── frontend/
│   ├── app/                           # Next.js App Router pages
│   ├── components/
│   │   ├── gap/                       # Gap analysis UI
│   │   ├── intelligence/              # Copilot, explanations, drafts
│   │   ├── portfolio/                 # Portfolio analytics
│   │   ├── program/                   # Program intelligence
│   │   ├── impact/                    # Change impact
│   │   ├── gates/                     # Gates panel
│   │   ├── scenarios/                 # Simulation tab
│   │   ├── documents/                 # Document management
│   │   ├── chat/                      # RAG chat
│   │   ├── copilot/                   # Co-pilot tab
│   │   ├── layout/                    # Header, Sidebar
│   │   └── common/                    # Shared UI primitives
│   ├── lib/
│   │   └── utils.ts
│   ├── package.json
│   ├── tailwind.config.js
│   └── tsconfig.json
│
├── docker-compose.yml
├── .env.example
├── .gitignore
└── README.md
```

---

## Deployment

MedComplyAI is closed source. This repository carries the deployment topology,
not the application. The stack runs from [`reference/`](reference/): Qdrant and
Ollama are public upstream images and start for anyone, while the backend and
frontend pull **private** images and need registry access.

### Host requirements

| | |
|---|---|
| Docker | Desktop 24+, or Engine with Compose V2 |
| RAM | 16 GB minimum, 32 GB recommended |
| Disk | 20 GB free for models and vector data |
| GPU | NVIDIA with CUDA drivers, strongly recommended |

GPU is optional and opt-in. The base compose file runs Ollama on CPU, which is
functional but materially slower for 7B inference. Enable a GPU with the
overlay described below. It is deliberately not in the base file: an `nvidia`
device reservation makes `docker compose up` fail outright on any host without
the NVIDIA container toolkit, rather than degrading to CPU.

### Ports

| Service | Port |
|---|---|
| Frontend | 3000 |
| Backend API | 8000 |
| Qdrant | 6333, 6334 (gRPC) |
| Ollama | 11434 |
| Langfuse (optional) | 3030 |

### Start the stack

```bash
git clone https://github.com/Sayantansaha27-tech/MedComplyAI.git
cd MedComplyAI/reference

# Backend and frontend are private images
gh auth token | docker login ghcr.io -u <your-github-user> --password-stdin

cp ../.env.example .env
docker compose up -d
```

All four services report healthy in roughly 20 seconds:

```
SERVICE    STATUS
backend    Up (healthy)
frontend   Up
ollama     Up (healthy)
qdrant     Up (healthy)
```

```bash
curl http://localhost:8000/api/v1/meta/health
# {"status":"ok","components":{"backend":"ok","vectorStore":"ok","ollama":"ok"}}
```

Without the `docker login`, Qdrant and Ollama start and the two application
images fail to pull. That is the expected result for a closed-source product,
not a broken compose file.

### Pull the models

Models are not baked into the images. Ollama starts empty, so pull all three
before running an analysis.

```bash
# Main inference model (~4.7 GB)
docker exec medcomplyai-ollama ollama pull qwen2.5:7b-instruct

# Embedding model (~1.5 GB)
docker exec medcomplyai-ollama ollama pull rjmalagon/gte-qwen2-1.5b-instruct-embed-f16

# Vision model for scanned PDFs (optional, ~1.5 GB)
docker exec medcomplyai-ollama ollama pull qwen3-vl:2b-thinking
```

Then open `http://localhost:3000`.

### Overlays

```bash
# NVIDIA GPU acceleration for Ollama
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d

# Langfuse LLM observability, dashboard on :3030
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
```

The observability overlay requires `LANGFUSE_NEXTAUTH_SECRET`, `LANGFUSE_SALT`,
and `LANGFUSE_DB_PASSWORD`. It refuses to start if any is unset or empty rather
than falling back to a default. Generate each with `openssl rand -base64 32`.

### Operational notes

- State lives in named volumes, so `docker compose down` without `-v` preserves
  the vector store and database. `down -v` destroys both.
- The images contain no data. No vector store, no database, no ingested
  documents. All state is created at first run.
- Healthchecks deliberately avoid `curl`, which none of the base images ship.
  See [`reference/README.md`](reference/README.md).

---

## Configuration

All backend configuration is managed via environment variables (see `.env.example`).

Key settings:

| Variable | Default | Description |
|---|---|---|
| `QDRANT_URL` | `http://localhost:6333` | Qdrant vector DB URL |
| `OLLAMA_URL` | `http://localhost:11434` | Ollama inference URL |
| `LLM_MODEL_ID` | `qwen2.5:7b-instruct-fixed` | Main LLM model tag |
| `EMBEDDING_MODEL_ID` | `rjmalagon/gte-qwen2-1.5b-instruct-embed-f16` | Embedding model tag |
| `GLASSBOX_ENABLED` | `true` | Enable grounding validation |
| `GROUNDING_BLOCK_ON_FAILURE` | `true` | Reject ungrounded outputs |
| `ENABLE_ISO14971_AUDIT` | `false` | Enable ISO 14971 advanced audit |
| `ENABLE_MDR_GSPR_AUDIT` | `false` | Enable MDR Annex I audit |
| `ENABLE_LANGFUSE` | `false` | Enable Langfuse observability |
| `GAP_MAX_CONCURRENT_RUNS_PER_TENANT` | `1` | Run concurrency limit |

**Framework flags** (enable in advanced gap analysis):

```env
ADV_GAP_ENABLE_CTD=true        # CTD Module compliance
ADV_GAP_ENABLE_MDR=true        # EU MDR Annex I
ADV_GAP_ENABLE_ISO=true        # ISO 14971 risk management
ADV_GAP_ENABLE_510K=true       # FDA 510(k) requirements
ADV_GAP_ENABLE_DRUG_LABELING=true  # Drug label (SmPC/PI)
ADV_GAP_ENABLE_DEVICE_IFU=true     # Device IFU requirements
```

---

## API Reference

The API is versioned at `/api/v1/`. Interactive docs at `http://localhost:8000/docs`.

**Core endpoints:**

```
POST   /api/v1/documents/upload            Upload documents
POST   /api/v1/ingestion/ingest/{doc_id}   Ingest document into vector DB

POST   /api/v1/chat/query                  RAG chat query
GET    /api/v1/chat/history                Conversation history

POST   /api/v1/gap/run                     Start gap analysis run
GET    /api/v1/gap/runs/{run_id}/status    Poll run status
GET    /api/v1/gap/runs/{run_id}/result    Get gap results + snapshot

POST   /api/v1/gap/advanced/run            Start advanced gap run
GET    /api/v1/gap/advanced/{run_id}/status

POST   /api/v1/intelligence/explain        Explain evidence for a requirement
POST   /api/v1/intelligence/copilot/query  Grounded copilot query
POST   /api/v1/intelligence/draft          Generate document draft from template
GET    /api/v1/intelligence/review-queue   List pending review items

GET    /api/v1/portfolio/compare           Compare two runs (delta)
GET    /api/v1/portfolio/timeline/{product} Product compliance timeline

GET    /api/v1/program/risk-register       Cross-product risk register
GET    /api/v1/program/root-cause/{req_id} Root cause analysis
GET    /api/v1/program/remediation/{req_id} Remediation playbook

POST   /api/v1/impact/analyze              Change impact simulation
POST   /api/v1/scenarios/simulate          Scenario simulation

GET    /api/v1/gates/summary/{run_id}      Submission gate status
POST   /api/v1/gates/evaluate/{run_id}     Evaluate gates for a run

GET    /api/v1/meta/health                 Health check
GET    /api/v1/meta/version                Engine version info
```

---

## Data Privacy & Security

- **All inference is local.** Documents and queries never leave your infrastructure. Ollama runs entirely within your Docker network.
- **No telemetry.** The application does not phone home.
- **Langfuse is optional.** If enabled, only LLM prompt/response metadata is sent to the configured Langfuse instance (cloud or self-hosted).
- **Storage is filesystem-based.** Uploaded documents are stored under `backend/storage/`. In production, mount this to a secure volume and configure access controls.
- **SQLite is development-grade.** For production multi-tenant deployments, replace the SQLite backend with PostgreSQL by updating `DATABASE_URL` in settings.

---

## Roadmap

- [ ] PostgreSQL backend support
- [ ] Multi-tenant authentication (OAuth2 / SAML)
- [ ] EMA EPAR / PMSR structured parsing
- [ ] ICH E3/E8 study report compliance templates
- [ ] ISO 13485 QMS document traceability
- [ ] Automated PSUR / DSUR generation
- [ ] EU MDR Technical Documentation completeness checker
- [ ] MedDRA coding integration for adverse event sections
- [ ] Webhook notifications for run completion
- [ ] Kubernetes Helm chart

---

## Documentation

| | |
|---|---|
| [`docs/00-problem.md`](docs/00-problem.md) | The problem in the customer's words |
| [`docs/01-scope-and-non-goals.md`](docs/01-scope-and-non-goals.md) | What this deliberately does not do |
| [`docs/02-architecture.md`](docs/02-architecture.md) | Ingestion, retrieval, gap engine, gateway |
| [`docs/03-decisions.md`](docs/03-decisions.md) | ADRs, including options that were rejected |
| [`docs/04-integration-contracts.md`](docs/04-integration-contracts.md) | Schemas, API surface, error codes |
| [`docs/05-failure-modes.md`](docs/05-failure-modes.md) | What has actually broken, and how it was found |
| [`docs/06-evals.md`](docs/06-evals.md) | Measured numbers, with the method stated |
| [`docs/07-runbook.md`](docs/07-runbook.md) | Install, upgrade, rollback, backup, triage |
| [`docs/08-handoff.md`](docs/08-handoff.md) | Running it without the person who built it |
| [`docs/09-postmortem.md`](docs/09-postmortem.md) | What would be done differently |
| [`reference/README.md`](reference/README.md) | Deployment topology and image details |

---

*MedComplyAI is not a substitute for qualified regulatory affairs professionals. It is a tool to augment and accelerate compliance review, not to replace human judgment. All AI outputs should be reviewed by a qualified person before use in regulatory submissions.*
