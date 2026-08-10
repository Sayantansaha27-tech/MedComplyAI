# Architecture

Four subsystems: ingestion, retrieval, the gap engine, and the LLM gateway. The
boundary that matters most is between the gap engine, which decides, and the
gateway, which explains. They do not overlap.

## System topology

```mermaid
flowchart TB
    subgraph host["Customer host, no outbound inference"]
        FE["Next.js frontend<br/>:3000"]
        BE["FastAPI backend<br/>:8000"]
        QD[("Qdrant<br/>:6333")]
        OL["Ollama<br/>:11434"]
        DB[("SQLite<br/>runs, snapshots,<br/>governance")]
    end

    FE -->|REST| BE
    BE -->|vectors + payloads| QD
    BE -->|inference| OL
    BE -->|state| DB

    style host fill:none,stroke:#888,stroke-dasharray: 4 4
```

No component reaches the public internet at inference time. There is no hosted
model client in the dependency tree, so the guarantee is enforced by absence
rather than configuration.

## Ingestion

```mermaid
flowchart LR
    A["PDF / DOCX"] --> B["Parser<br/>section detection"]
    B --> C["Hierarchical chunker"]
    C --> D["Parent chunk<br/>~3000 chars, max 4500"]
    C --> E["Child chunk<br/>max 1200 chars"]
    E --> F["Embed<br/>gte-qwen2-1.5b"]
    F --> G[("Qdrant")]
    D -.->|parent_text carried<br/>on every child| E
```

Chunking is structural, not fixed-width. Documents split at detected section
boundaries, and each chunk carries the hierarchy it came from: `section_path`,
`section_title`, `section_number`, `semantic_label`, `chunk_type`, `parent_id`,
`chunk_index`, `page_span`.

Parent and child are stored together. Retrieval matches against the small child
chunk for precision, then hands the model the parent text for context. This is
why a match on a two-line clause still arrives with the surrounding section
attached.

Scanned PDFs route through a vision model. Extraction quality on poor scans is
not guaranteed and is not measured; see [`06-evals.md`](06-evals.md).

## Retrieval

Hybrid, with an intent classifier in front of it.

```mermaid
flowchart TB
    Q["Query"] --> IC["Intent classifier<br/>keyword + regex, no LLM"]
    IC -->|regulatory_citation| RK["Regulatory KB<br/>curated clause text"]
    IC -->|factual_lookup| HR["Hybrid retrieval"]
    IC -->|comparison| HR
    RK --> CTX["Context assembly"]
    HR --> CTX
    HR --> D["Dense<br/>embedding similarity"]
    HR --> S["Sparse<br/>keyword score"]
    HR --> M["Metadata filter<br/>section, doc_type, authority"]
    CTX --> GW["LLM Gateway"]
```

The intent classifier is deterministic: keyword and regex only, no model call. It
decides retrieval strategy before any inference happens.

When intent is `regulatory_citation`, curated regulatory text is injected as a
distinct `[Regulatory Reference]` block. The model can then separate *what the
regulation requires* from *what the customer's document says*, which are
different claims that must not blur together in an audit context.

## Gap engine

This is where decisions are made, and no LLM participates.

```mermaid
flowchart TB
    R["Requirement registry"] --> EV{"Framework"}
    EV -->|ISO 14971| I["iso14971_evaluator<br/>no LLM imports"]
    EV -->|MDR Annex I| M["mdr_ifu_coverage<br/>no LLM imports"]
    EV -->|other frameworks| G["generic LLM path<br/>proposes severity only"]

    I --> SC["Keyword classifier<br/>strong / weak cues,<br/>structural checks"]
    M --> SC
    SC --> ST["decide_status()<br/>pure boolean branching"]
    ST --> OUT["met / partial /<br/>not_met / not_assessed"]

    style I fill:#1b4332,color:#fff
    style M fill:#1b4332,color:#fff
    style ST fill:#1b4332,color:#fff
```

`decide_status()` takes booleans and returns a status. Given the same evidence it
returns the same answer, every time, with no temperature and no sampling.

The scoping is honest and worth stating plainly: for ISO 14971 and MDR Annex I
the evaluators contain no LLM calls at all. Other frameworks route through a
schema-agnostic path where the model proposes a finding severity. In no case does
model output write a coverage status, verdict, or `met` field. That boundary is
absolute across the system.

## LLM Gateway

The gateway's job is to make ungrounded output unreachable, not to flag it.

```mermaid
flowchart TB
    P["Build prompt:<br/>'Answer ONLY using<br/>evidence IDs [E1, E2...]'"] --> C["Ollama<br/>temperature 0.1"]
    C --> J["Parse JSON"]
    J --> V["Grounding validator v2.3"]
    V --> CH{"passes?"}
    CH -->|yes| OK["Return to caller"]
    CH -->|no, attempts left| RP["Repair prompt<br/>with the errors"]
    RP --> C
    CH -->|no, exhausted| FB["Fallback object:<br/>is_fallback, message,<br/>grounding_errors"]

    style FB fill:#7f1d1d,color:#fff
    style OK fill:#1b4332,color:#fff
```

The validator checks schema, verbatim quotes against their span, field
references, citation IDs existing in the evidence index, summary factuality, and
numbers appearing in a `FieldReference` or an allowed aggregate.

On failure the gateway retries with a repair prompt carrying the specific errors,
up to `MAX_RETRIES = 2`, so three attempts total. If all fail it returns a
fallback object containing only `is_fallback`, a message, and the grounding
errors.

**The ungrounded model text is discarded.** It is not returned, not attached, not
logged into the response. That is the difference between blocking and flagging,
and it is the reason the grounding claim survives scrutiny.

Deterministic query types, `STATUS`, `LIST`, `SUMMARY`, and `COMPARE`, bypass the
model entirely and are answered from snapshot data.

## State and snapshots

```mermaid
flowchart LR
    RUN["Gap run"] --> SNAP["Snapshot<br/>canonical JSON"]
    SNAP --> H["SHA-256<br/>engine_status_hash"]
    H --> BIND["Run binding:<br/>run_id + snapshot_id + hash"]
    BIND --> LLM["Every LLM interaction<br/>carries the binding"]
    SNAP --> CMP["Compare across runs"]
    SNAP --> EXP["Audit bundle export<br/>bundle_hash"]
```

Snapshots are written through a single append-only path. There is no update or
delete. The hash uses `json.dumps(payload, sort_keys=True)` with SHA-256, and
bundle hashes use the blank-the-field-then-hash pattern so the hash covers the
payload it is stored in.

Two limits, stated because they are easy to overclaim: the hash is a **provenance
stamp**, binding an interaction to an engine state, not a tamper check, because
nothing recomputes and compares it. And append-only is enforced by there being
one write path, not by a database constraint.

Snapshot replay is not implemented. Compare and export are.
