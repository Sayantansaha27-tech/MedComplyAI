# Decision records

Each record states the decision, what was rejected, and what it costs. The
rejected options matter as much as the chosen ones.

---

## ADR-001: Local open-weight models, no cloud inference

**Decision.** All inference runs on the deployment host via Ollama. Qwen 2.5 7B
for generation, gte-qwen2-1.5b for embeddings.

**Rejected: hosted frontier APIs.** Better output quality, no GPU requirement,
no model operations. Rejected because customers cannot send this material to a
third-party API under 21 CFR Part 11 and internal governance, and several are
contractually barred by their own clients. A product they cannot install is worth
nothing regardless of output quality.

**Rejected: cloud API with a no-retention agreement.** Insufficient. The
requirement is that documents never transit third-party infrastructure at all,
not that they are deleted afterwards.

**Cost.** A 7B model is meaningfully weaker than a frontier model. The system
compensates with retrieval quality and by keeping the model out of every decision
that matters. Customers need a GPU for acceptable latency.

**Enforcement.** No hosted-model client exists in the dependency tree. The
guarantee holds by absence, not configuration, so it cannot be undone by an
environment variable under deadline pressure.

---

## ADR-002: Deterministic classifiers decide coverage, LLMs only narrate

**Decision.** For ISO 14971 and MDR Annex I, coverage is decided by keyword
classifiers and pure boolean logic. No LLM output may write a status, verdict, or
coverage field anywhere in the system.

**Rejected: LLM-as-judge.** Standard, flexible, far less code. Rejected because
the output has to survive an inspection. "The model assessed this as adequate" is
not a defensible answer, and a non-deterministic judge means the same dossier can
produce two different answers on two runs, which is disqualifying for an audit
artifact.

**Rejected: LLM decides, deterministic rules validate.** Attractive because it
keeps the flexibility. Rejected because it inverts responsibility: the rules
become a filter on a guess rather than the decision procedure, and every
disagreement needs a tiebreak policy that is itself unauditable.

**Cost.** Every framework needs hand-written evaluators and keyword taxonomies.
Adding a framework is real work, not a prompt. Nuance a model would catch is
missed unless someone encodes it.

**Consequence.** Given the same evidence the system returns the same answer every
time, and the reasoning is a code path a reviewer can read.

---

## ADR-003: Structural chunking, not fixed-width

**Decision.** Split at detected section boundaries with hierarchy preserved.
Parent chunks ~3000 chars, children max 1200, `parent_text` carried on every
child.

**Rejected: fixed-size sliding window.** Trivial to implement and works fine for
question answering. Rejected because it destroys the thing the domain runs on. A
requirement is satisfied by "section 4.3 of the Risk Management File", and a
chunk that spans the boundary between 4.2 and 4.3 cannot support that citation.
Absence detection also becomes unreliable: you cannot say "we searched section 7
and found nothing" if your chunks do not know what section 7 is.

**Cost.** Parsing is fragile on documents with inconsistent heading structure,
and scanned PDFs need a vision model. Chunks vary in size, which complicates
context budgeting.

---

## ADR-004: Parent-child retrieval

**Decision.** Match against small child chunks, return parent text to the model.

**Rejected: single chunk size.** Either precision or context suffers. Large
chunks dilute the embedding and match poorly on specific clauses; small chunks
match well but arrive without the surrounding text needed to judge them.

**Cost.** Storage duplication, since `parent_text` is denormalised onto every
child. Accepted deliberately: it removes a second lookup from the hot path and
storage is cheap relative to latency.

---

## ADR-005: Grounding failures block, they do not flag

**Decision.** Ungrounded output is discarded. The gateway retries with a repair
prompt up to three attempts, then returns a fallback object containing only an
error.

**Rejected: return output with a confidence warning.** Common and much friendlier.
Rejected because a warning next to a fabricated citation is still a fabricated
citation in a document heading toward a regulator. Users under time pressure read
the answer and not the warning, and the failure mode is silent.

**Rejected: flag for human review, show it anyway.** Same problem. Once a
plausible fabricated citation is on screen it anchors the reviewer.

**Cost.** Users sometimes get "AI could not produce a grounded response" instead
of an answer. That is the correct outcome, and it is the behaviour the product
sells.

---

## ADR-006: Absence is a first-class result

**Decision.** Status distinguishes `met`, `partial`, `not_met`, and
`not_assessed`. "Searched and absent" and "out of scope" are different answers.

**Rejected: binary met / not met.** Collapses two very different situations. A
requirement that does not apply to this product class and a requirement that
applies and is missing need different actions, and conflating them either creates
false work or hides real gaps.

---

## ADR-007: Private container images, not public

**Decision.** Backend and frontend images published to GHCR as private packages.

**Rejected: public images so anyone can run it.** Strongest demo, and briefly
tempting. Rejected on a technical fact: a Python application image contains
readable `.py` source. `docker cp` retrieves every file. Publishing images
publicly *is* publishing the source, in a less convenient format. That would have
reversed the closed-source decision by side effect.

**Rejected: publish nothing, document only.** Leaves a reader unable to start
anything and makes the deployment topology unverifiable.

**Cost.** Anyone without registry access gets Qdrant and Ollama up and a pull
failure on the two application services. That is the honest shape of a
closed-source product and is documented as expected behaviour rather than left to
look like a bug.

---

## ADR-008: Compose overlays instead of profiles

**Decision.** GPU and observability live in separate compose files, combined with
`-f`, rather than behind `profiles:`.

**Rejected: compose profiles.** The idiomatic mechanism, and the first
implementation used it. Rejected after it failed in practice: Compose interpolates
the entire file before filtering by profile, so a required-variable check on a
profiled service breaks the core stack even when that profile is inactive.
Verified directly, `docker compose config --services` failed with observability
switched off.

The same class of problem applies to the GPU reservation. An `nvidia` device
reservation fails the whole `up` on hosts without the container toolkit rather
than degrading to CPU.

**Cost.** Longer commands for optional capability. Worth it: the base stack now
starts on any host with no configuration at all.

---

## ADR-009: Single-tenant on-premise, not multi-tenant SaaS

**Decision.** One deployment per customer, no shared infrastructure, no control
plane.

**Rejected: multi-tenant SaaS.** Better economics and far easier upgrades.
Incompatible with ADR-001: if documents cannot leave the customer environment,
there is no shared environment to put them in.

**Cost.** Upgrades are manual and per-customer. No aggregate telemetry, so
failure modes are learned by being told rather than observed. Support is
high-touch.

**Regret, in part.** The governance layer, submission packs and weight policies
with lifecycle states and approval workflows, was built for a plural-user
deployment that did not exist yet. Its tables contain only test fixtures. See
[`09-postmortem.md`](09-postmortem.md).
