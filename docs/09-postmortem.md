# Postmortem

What I would do differently. Written after the system was already deployed and
in paid use, which is the only point at which most of this becomes visible.

---

## 1. I published a deployment topology I had never run

The single worst thing in this project. `docker-compose.yml` and both Dockerfiles
sat in the public repository, referenced by a Quick Start section, for months.
Nobody had ever executed them, including me. My actual workflow was
`start_backend.sh` and `start_frontend.sh` running uvicorn and npm directly.

When they were finally run, seven defects surfaced. Four of them independently
prevent the stack from starting. The healthcheck failure was the worst: every
probe called `curl`, which is absent from all three base images, so services that
were working perfectly reported `unhealthy` forever and the dependency chain
deadlocked silently.

**What I would do differently.** Never publish an artifact that claims to be
runnable without a check that runs it. The fix is cheap: one CI job doing
`docker compose up -d`, wait for health, `curl` the health endpoint, tear down.
Twenty lines. It would have caught all four blocking defects on the first commit.

**The deeper mistake** was treating deployment config as documentation rather
than code. Documentation drifts and the cost is confusion. Deployment config
drifts and the cost is that nobody can install your product. I had written it
carefully, which made it look finished. Careful and executed are different
properties.

---

## 2. I had no .gitignore, and the vector store went into git

The source repository tracked 64,032 files against 443 files of actual source.
The virtualenv, `node_modules`, build output, logs, the database, and a 236 MB
Qdrant vector store were all committed.

The vector store payloads hold the plaintext of every ingested document.

This was contained by accident. That repository has no remote and has never been
pushed. Had I ever run `git remote add` and `git push`, the entire document corpus
and all application source would have gone public in one command, and the
closed-source decision would have been reversed by a reflex.

**What I would do differently.** Write `.gitignore` in the first commit, before
the first `git add`. It is thirty seconds of work at the start and unbounded
cleanup later, because history is permanent. The data is still in the initial
commit. Untracking fixed the future; the past needs a history purge that has not
been done because it is not needed while the repo stays local.

**The uncomfortable part** is that I built a compliance product, whose entire
value proposition is that customer documents stay under the customer's control,
and I had customer-adjacent document text sitting unignored in version control on
a laptop. The gap between the standard I designed the software to and the
standard I operated at was large.

---

## 3. I let the README's claims drift from the code

The README is the strongest writing in the project and makes precise, falsifiable
architectural claims. When they were checked line by line against the
implementation, chunk sizes were stale by a factor of nearly two, "hash-verified"
described something that never verifies anything, and "the snapshot can be
replayed" described a feature that does not exist.

The claims were true when written. The code moved.

**Why it matters more here than in most projects.** The product's differentiator
is that its determinism and grounding guarantees are *checkable*. A reviewer who
verifies one claim and finds it unsupported now has reason to doubt the ones that
are true and load-bearing, like the grounding gateway genuinely blocking
ungrounded output, which is real and well built.

**What I would do differently.** Treat the numbers in architecture docs as
testable assertions. Chunk sizes belong in one constants module that the docs
quote from, or a test that fails when the docs and the code disagree. Prose that
restates a constant will drift; the only question is when.

---

## 4. I built for a plural customer I did not have

There is a governance layer with submission policy packs, weight policies,
lifecycle states (`DRAFT`, `ACTIVE`, `RETIRED`), approval workflows, and
`created_by` / `approved_by` / `activation_by` audit fields.

The database rows for it are all test fixtures. Titles are `pt` and `pd`. Every
actor is `tester`. The `documents`, `chunks`, `sections`, `ai_outputs`, and
`llm_interactions` tables are empty.

This is machinery for a multi-user, multi-org deployment built before a
multi-user, multi-org customer existed.

**What I would do differently.** Build the governance layer when the second
approver appears, not in anticipation of them. The work is not wasted exactly,
the schema is sound, but it was capital spent on a hypothesis instead of on the
things that were actually broken, like a deployment path that did not work.

**The tell I missed:** when the only rows in a table are ones you wrote to test
the table, that feature has no user yet.

---

## 5. Determinism was the right call, and I nearly undersold it

The one large decision that held up completely.

Coverage for ISO 14971 and MDR Annex I is decided by deterministic keyword
classifiers. Those evaluators import no LLM client. No path anywhere lets model
output write a status or verdict. The grounding gateway genuinely blocks
ungrounded output: validation failure triggers a repair prompt, retries, and on
exhaustion returns a fallback object containing only an error, discarding the
model text entirely. The user never sees an ungrounded claim.

That is the product. It is what makes the output defensible in an audit, and it
is a real engineering boundary rather than a prompt instruction.

**And the README described it as "hard-coded rules first, LLM fallback second"**,
which implies an LLM fallback that decides coverage. There is no such fallback.
I made my strongest guarantee sound weaker and more conditional than it is.

**What I would do differently.** State the strong version and make it checkable.
"No LLM writes a coverage status anywhere in this system, and you can verify that
by reading two files" is both true and far more compelling than hedged phrasing.

---

## 6. Things I got right and would repeat

- **Local-only inference as an architectural constraint, not a config flag.**
  There is no cloud client to accidentally enable. The constraint is enforced by
  absence, which is the only enforcement that survives a deadline.
- **Canonical JSON hashing.** `sort_keys` with SHA-256, and the blank-the-field-
  then-hash pattern for bundle hashes, is textbook and was right the first time.
  The gap is that nothing verifies the hashes, not the hashing itself.
- **Refusing to output a filing decision.** Sustained pressure to add it. Holding
  that line kept the product on the correct side of a regulatory boundary.

---

## The pattern

Four of the five failures above are the same failure: **I trusted artifacts I had
never executed.** A compose file never run. A `.gitignore` never written. README
claims never re-checked. A governance layer never used by a real second user.

Each was carefully made, which is exactly what made them easy to trust.

The cheap correction is a bias toward execution over inspection. Run the compose
file. Grep the code for the claim. Query the table and look at who the actors
really are. Every defect in [`05-failure-modes.md`](05-failure-modes.md) was found
in minutes once something actually ran, after surviving months of being looked at.
