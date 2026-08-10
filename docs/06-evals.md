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

---

## Not measured

Stated plainly rather than left as an implication.

### Coverage classification accuracy

There is no labelled test set. Precision and recall of the ISO 14971 and MDR
Annex I classifiers against expert-assigned ground truth are unknown.

This is the most important missing number. The determinism argument in
[ADR-002](03-decisions.md) establishes that the system gives the *same* answer
every time. It does not establish that the answer is *correct*. Those are
different properties and only one of them has been demonstrated.

**What it would take.** Perhaps 50 to 100 requirement-document pairs labelled by
a qualified reviewer, held out, scored for precision and recall per requirement
class. The evaluators are deterministic, so the run is cheap and repeatable once
the labels exist. The labelling is the expensive part and is the reason it has not
been done.

### Grounding validator effectiveness

The gateway blocks ungrounded output; that is verified by reading the code path
and confirming the fallback carries no model text. What is unmeasured:

- How often grounding fails in normal operation
- How often the repair prompt rescues a failed attempt within three tries
- False positives, where a correctly grounded answer is rejected

The interaction log records `grounding_passed` per attempt, so this is
computable from existing data. It has not been computed.

### Retrieval quality

No measurement of recall@k, or of how often the correct evidence chunk appears in
the retrieved set. Chunking and hybrid retrieval decisions in
[ADR-003](03-decisions.md) and [ADR-004](03-decisions.md) were made on domain
reasoning, not on an ablation.

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

1. **Labelled coverage set.** 50 to 100 requirement-document pairs scored by a
   qualified reviewer. Unblocks precision and recall, and the evaluators are
   deterministic so the run is cheap and repeatable once labels exist.
2. **Grounding statistics.** Computable today from `grounding_passed` in the
   existing interaction logs. No new instrumentation required.
3. **Retrieval recall@k**, using the same labelled set from step 1.
