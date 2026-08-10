# Scope and non-goals

What this system does, and more importantly what it deliberately refuses to do.
The non-goals are load-bearing. Several of them are the reason customers trust
the output.

## In scope

- **Structural ingestion** of PDF and DOCX regulatory documents, split at
  section boundaries with hierarchy preserved.
- **Coverage assessment** against ISO 14971 and MDR Annex I using deterministic
  keyword classifiers.
- **Gap findings** between a standard document and a test document across
  additional frameworks (ISO 13485, CTD, 510(k), drug labeling, device IFU).
- **Grounded explanation** of why a requirement was marked met, partial, or not
  met, with span-level citations into the source document.
- **Readiness scoring** as a weighted, policy-driven indicator for internal
  planning.
- **Audit bundles**: canonically serialised, hashed exports of a run.
- **On-premise operation** with no outbound inference calls.

## Non-goals

### It does not decide regulatory outcomes

The system produces coverage status and readiness scores. These are inputs to a
qualified regulatory affairs professional, not a substitute for one. Readiness
scores are explicitly labelled in the data model as "policy-based indicators for
planning" and carry a non-regulatory disclaimer on every submission pack.

Nothing here should be filed. A human decides what gets filed.

### The LLM never decides pass or fail

For ISO 14971 and MDR Annex I, coverage is decided by deterministic classifiers.
The evaluators import no LLM client. No code path anywhere in the system lets
model output write a status, verdict, or coverage field.

This is a hard architectural boundary, not a policy that could be relaxed under
deadline. If a reviewer asks "could the model have changed this result", the
answer is no, and it is checkable by reading two files.

The LLM writes prose. That is all it does.

### It does not send anything to a cloud API

There is no OpenAI client, no Anthropic client, no hosted inference endpoint
anywhere in the stack. Inference is Ollama on the deployment host. This is not
a configuration default that could be flipped; there is no code path to flip.

Customers in this segment cannot send IP-adjacent or patient-adjacent documents
to third-party APIs under 21 CFR Part 11 and internal governance. A product that
could leak is a product they cannot install.

### It is not a document management system

It does not version customer documents, manage approval workflows, or act as the
system of record. It reads documents, indexes them, and produces findings. The
customer's existing eQMS remains the system of record.

### It is not multi-tenant SaaS

Each deployment is a single-tenant on-premise install. There is no shared
database, no cross-customer index, no central control plane. Concurrency limits
are per-tenant but the intended topology is one tenant per install.

This costs scalability and makes upgrades manual. It is the correct trade for
the segment.

### It does not do OCR-quality guarantees on scanned documents

A vision model handles scanned PDFs, but extraction quality on poor scans is not
guaranteed and is not measured. Documents that fail to parse cleanly should be
re-sourced as native PDF or DOCX rather than trusted.

### It does not replay snapshots

Snapshots are hashed, comparable across runs, and exportable. They cannot
currently be re-executed to reproduce a historical result from scratch. This is
a known gap, stated here rather than implied away. See
[`09-postmortem.md`](09-postmortem.md).

### It does not verify its own integrity hashes

Snapshot hashes are computed and stored correctly. Nothing recomputes and
compares them, so the hash is a provenance stamp binding an LLM interaction to an
engine state, not a tamper-detection mechanism. Also a known gap.

## Where the boundary gets pressure

The most common request is "can it just tell us if we are ready to file". The
answer is no, and holding that line is the product. A tool that outputs a filing
decision would need to be validated as a medical device software component in
its own right in some jurisdictions, and would carry liability the product is
not structured to hold.

The second most common request is a hosted version. Same answer, for the reason
in the non-goal above.
