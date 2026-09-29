# Evaluation

This document separates what has been measured from what has not. The unmeasured
list is the longer of the two, and it is set out explicitly rather than left as an
implication. Nothing below is extrapolated.

The vocabulary is used strictly:

- **Measured** means observed in a production deployment.
- **Benchmarked** means observed in a stated evaluation run.
- **Modelled** means an assumption-driven estimate.

---

## Measured

### Review cycle time

| | Before | After |
|---|---|---|
| Verification cycle for one product review | 4 to 5 days | 4 to 5 hours |

**Method.** Observed across real consulting engagements before and after
deployment. The unit is the same task: cross-referencing a product dossier
against a framework's requirements and producing a defensible coverage map with
evidence attached.

**What it does not isolate.** This is a workflow measurement, not a model
benchmark. It compares a human reading everything against a human reviewing
machine-proposed evidence. It does not tell you the system's precision or recall,
and it should not be quoted as if it did. The gain comes mostly from shifting
*finding* evidence to *reviewing* evidence, which is a faster job regardless of
how good the underlying retrieval is.

**Confounders, stated.** Reviewers were familiar with the dossiers by the second
pass. Sample size is small, single-digit engagements. No control group.

### Deployment characteristics

Observed on a clean `docker compose down -v` followed by `up -d`, Apple Silicon,
CPU inference, no GPU:

| | |
|---|---|
| All four services healthy | ~20 seconds |
| Frontend first response | HTTP 200, Next.js ready in 24 ms |
| Backend image | 600 MB content |
| Frontend image | 55 MB content |

**Method.** Single observation on one host, recorded during the deployment
verification described in [`05-failure-modes.md`](05-failure-modes.md). Not
averaged across runs or hardware. Model pull time is excluded and dominates real
first-boot time: roughly 7.7 GB across three models.

### End-to-end verification, 21 September 2026

Full pipeline exercised against two synthetic drug documents (a CCDS as the
reference, an EU SmPC-style local label as the document under review), on an M3
with 16 GB, natively served models, image 0.1.2.

| Step | Result |
|---|---|
| Upload and ingest 2 documents | 13 chunks, 1024 dimensions |
| RAG chat | grounded answer with 2 citations, ~11 s warm |
| Advanced gap run | SUCCEEDED, ~8 minutes |
| Deterministic coverage | **32 requirements**: 12 ISO 14971, 14 MDR GSPR, 6 MDR |
| Deterministic findings | 16, including 4 critical ISO 14971 |
| LLM findings | 5 across the generic and drug-label engines |
| Audit bundle | HTTP 200, `coverage_hashes_verified: true`, 32 items |
| Tamper detection | Flipping a stored status to `met` produced `verified: false` naming that requirement; restoring it returned `true` |

The same run on the containerised, CPU-only Ollama took about 30 minutes, every
LLM engine exceeded its budget and returned zero findings, and the deterministic
coverage matrix was produced in full regardless. That is the clearest evidence
for the determinism boundary: the model contributed nothing and the compliance
engine still produced all 32 requirements and 16 findings.

Single observations on one host, not averaged, and not a substitute for the
accuracy measurement below.

---

## Benchmarked

### Coverage classifier detection, 21 September 2026

104 cases over all 26 deterministic requirements (12 ISO 14971, 14 MDR GSPR),
four per requirement: the literal target phrasing present, the same content
paraphrased, the keyword present inside a negation, and unrelated content.

**Ground truth is true by construction.** Each fixture was authored to contain or
omit the artifact, so no regulatory judgement is embedded in the labels. Scored as
detection (`met` or `partial`) rather than exact status, because the met/partial
split turns on evidence-quality heuristics that construction cannot adjudicate.

| Case type | Precision | Recall | n |
|---|---|---|---|
| Literal phrasing present | 1.00 | **1.00** | 26 |
| Content paraphrased | 1.00 | **0.08** | 26 |
| Keyword inside a negation | — | — | **26/26 correctly not detected** |
| Unrelated content | — | — | **26/26 correctly not detected** |
| **Overall** | **1.00** | 0.54 | 104 |

Per framework: ISO 14971 precision 1.00, recall 0.58. MDR GSPR precision 1.00,
recall 0.50. Identical across repeated runs, which is the determinism claim in
[ADR-002](03-decisions.md) measured rather than asserted.

**Method.** `backend/scripts/eval_coverage.py` calls the same two functions
`run_advanced_gap_analysis` calls, so it measures production code rather than a
reimplementation. Section titles in fixtures are neutral: the evaluators match
cues against the title as well as the body, and a title naming the requirement
leaks the answer. The first run had that flaw and reported precision 0.52 partly
as an artifact of it.

**What this establishes.** The engine does not invent coverage. No fixture
produced a false `met`, including the 26 that state the artifact is absent. It
detects the artifact whenever the target phrasing is present.

**What it does not establish.** Whether the requirement definitions are
regulatorily correct. A classifier can score 1.00 here while checking for the
wrong thing, and construction-based fixtures cannot detect that. See below.

**The real limitation it exposes.** Recall on paraphrased content is 0.08. A
document that describes the artifact in its own words is largely invisible to the
classifiers. Real documents often carry informative headings, which the evaluators
also read, so production recall is probably better than 0.08 — but by an unmeasured
margin.

### Answer verification and label comparison, 29 September 2026

Chat answers are checked sentence by sentence against the documents they cite,
and a reference label can be compared with a local label statement by statement.
Both use the same two tiers: deterministic rules (every number and unit must
appear in the sources, and no word may be a look-alike of a substance or product
name in them), then a local model asked whether each document supports each
statement.

**Chat claims:** 46 construction-based claims against the two reference labels,
21 true and 25 not. The false ones are dose and unit substitutions, look-alike
drug names, contradictions, fabrications, and statements true of one label but
not the other.

| | Recall | False flags | Median per check |
|---|---|---|---|
| Rules only | 0.44 | 0 of 21 | none |
| Rules + chat model (qwen2.5:7b, default) | **1.00** | **0 of 21** | 314 ms |
| Rules + Bespoke-MiniCheck-7B | 0.96 | 0 of 21 | 400 ms, plus a 14 s model swap on 16 GB |

The rules alone never flagged a true claim, and caught every dose, unit and
look-alike substitution. The model tier catches what rules cannot: contradictions,
fabrications, and cross-label statements.

**Label comparison:** the 51 statements of the reference CCDS checked against the
EU SmPC. 7 partial matches are marked ambiguous and not scored. Of the 44 scored,
38 are deviations. Precision 0.97, recall 0.97, with one of six present
statements flagged. The two disagreements with the answer key are both
defensible: a fever indication the SmPC carries without the CCDS's 40 kg weight
floor, and a contraindication the SmPC downgrades to a warning, which a checker
that does not read section context cannot see.

**On the running stack.** Asked the same dose question three times, the chat model
wrote "paracetamol" where both labels say "paracetronil" four times; the name rule
flagged all four. A correct side-by-side answer ("3000 mg (CCDS) / 4000 mg (EU
SmPC)") is reported as supported only when the sources are read together, and a
statement in one label and not the other is shown as such. One false flag
remains: a terse fragment such as "EU SmPC: 7 days" is sometimes rejected
although the SmPC says it. Verification adds 1 to 4 seconds to an answer.

**What this does not establish.** The sets are small and synthetic, and the label
answer key was written by an engineer, not a regulatory reviewer. The numbers
show the design works on the failure types it targets; they are not a general
accuracy claim. The chat model checking its own answers was the better verifier
here, but a verifier independent of the generator remains the stronger argument
in an audit, which is why MiniCheck stays available.

---

## Not measured

Stated plainly rather than left as an implication.

### Regulatory correctness of the requirement definitions

Detection is now benchmarked; correctness is not. Nothing has established that a
requirement, when the engine marks it met, is met *in the sense the regulation
intends*. That is a judgement about whether the keyword sets, structural checks and
acceptance rules encode the clause faithfully, and construction-based fixtures
cannot answer it: they only confirm the engine finds what it was told to look for.

The determinism argument in [ADR-002](03-decisions.md) shows the system gives the
same answer every time. The benchmark above shows it does not invent coverage.
Neither shows the answer is regulatorily right.

**What it would take.** 50 to 100 requirement-document pairs labelled by a
qualified reviewer, against real dossier text rather than authored fixtures, held
out and scored per requirement. The evaluators are deterministic, so the run is
cheap and exactly repeatable once the labels exist. The labelling is the expensive
part and remains the reason this is open.

### Recall on real documents

The paraphrase figure above (0.08) is a floor, not an estimate: fixtures use
neutral headings while real documents carry informative ones the evaluators also
read. The true production recall is somewhere above it and unmeasured.

### Grounding validator effectiveness

The gateway blocks ungrounded output; that is verified by reading the code path
and confirming the fallback carries no model text. What is unmeasured:

- How often grounding fails in normal operation
- How often the repair prompt rescues a failed attempt within three tries
- False positives, where a correctly grounded answer is rejected

These are now computable. The gateway persists every interaction, for every use
case, so `grounding_passed` is a query against `llm_interactions`. Verified on a
running stack: a Copilot explanation query writes a `copilot_narrative` row and
the pass rate comes straight out of the table.

What is still missing is volume. One query is not a measurement, so the numbers
above stay unreported until the log has real traffic behind it.

### Retrieval quality

No measurement of recall@k, or of how often the correct evidence chunk appears in
the retrieved set. Chunking and hybrid retrieval decisions in
[ADR-003](03-decisions.md) and [ADR-004](03-decisions.md) were made on domain
reasoning, not on an ablation.

Any impression of retrieval quality formed before 29 September 2026 describes
keyword retrieval alone: dense search returned nothing in every published image
until then (see [failure mode 13](05-failure-modes.md)). Hybrid retrieval has
only been working, and so only been measurable, since.

### Model comparison

Qwen 2.5 7B was selected on licence, size, and local-inference fit. No
head-to-head against comparable open-weight models on this task.

### Scanned document extraction

Vision-model extraction quality on poor scans is not characterised. Documents that
fail to parse cleanly should be re-sourced as native PDF or DOCX rather than
trusted.

### Latency under load

Single-run latency has not been recorded systematically, and concurrency is capped
at 1 per tenant by default, so multi-run behaviour is untested.

---

## Why the gaps exist, and what closes them

The system was built to a deployment deadline for a small number of customers who
evaluated it on whether their review got faster. It did, substantially, and that
was sufficient commercial validation to continue. Evaluation infrastructure was
never the constraint on the next piece of work, so it was never built.

This is a genuine gap. A product arguing that its determinism makes it auditable
should be able to state its accuracy. At present it can state its reproducibility
and its cycle time, and those are different claims.

**Priority order for closing it:**

1. **Expert-labelled coverage set.** 50 to 100 requirement-document pairs scored
   by a qualified reviewer against real dossier text. The harness and scoring
   already exist (`backend/scripts/eval_coverage.py`); only the labels are
   missing. This is what turns detection benchmarking into a correctness claim.
2. **Grounding statistics.** Unblocked: every gateway interaction is now
   persisted with its `grounding_passed` result. What remains is accumulating
   enough real traffic for the rate to mean anything.
3. **Retrieval recall@k**, using the same labelled set from step 1.
