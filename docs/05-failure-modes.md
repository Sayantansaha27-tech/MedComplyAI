# Failure modes

Things that were broken, how they were found, and what was done. Written from
actual incidents rather than a threat-modelling exercise. Where something is
still open it says so.

---

## 1. Observability stack shipped with default secrets

**Severity: high. Status: fixed.**

The Langfuse profile in `docker-compose.yml` carried silent fallbacks:

```yaml
NEXTAUTH_SECRET: ${LANGFUSE_NEXTAUTH_SECRET:-changeme-in-production}
SALT:            ${LANGFUSE_SALT:-changeme-in-production}
POSTGRES_PASSWORD: langfuse
```

An operator who never set the variables got a fully running observability stack
with publicly documented secrets and no warning at any point.

`.env.example` made it worse. It shipped `changeme-in-production` as a literal
value, so the documented setup path, copy the example to `.env`, produced exactly
the weak deployment the name warns against.

The Langfuse instance holds LLM interaction traces: prompts, retrieved evidence
spans, and model outputs. For a compliance product processing customer
regulatory documents, that is the most sensitive store in the deployment.

**Why it survived so long.** It was container-internal and not exposed to the
host, so it was never exploitable in the deployed topology. That made it easy to
classify as theoretical. It is not theoretical in a product whose entire pitch is
that sensitive documents stay under the customer's control.

**Fix.** Every fallback replaced with a required-variable check, so compose
refuses to start when a value is unset or empty and names the missing variable.

**The fix was wrong twice before it was right**, which is the useful part.

First attempt put the error hint inline unquoted. The colon inside
`generate with: openssl rand` terminated the YAML mapping and broke the file
entirely. Caught by `docker compose config`.

Second attempt worked but broke the core stack. Compose interpolates the whole
file before it filters by profile, so a required-variable check on a *profiled*
service fails the entire `up` even when that profile is inactive. With the
services still behind `profiles: ["observability"]`, `docker compose config
--services` failed with observability switched off. That would have made the
product unstartable for every customer not running Langfuse: a worse defect than
the one being fixed.

**Actual fix.** Langfuse moved to `docker-compose.observability.yml` as an
overlay. Secrets are mandatory there and irrelevant to the core stack.

Verified: core stack with vars unset starts; overlay with vars unset refuses and
names the variable; overlay with vars set starts; overlay with a var set to
empty string refuses.

---

## 2. The deployment topology had never been executed

**Severity: high. Status: fixed.**

The published `docker-compose.yml` and both Dockerfiles had never been built or
run by anyone, including the author. Local development ran uvicorn and npm
directly through shell scripts. The container path existed only as documentation.

Running it end to end for the first time surfaced seven defects. Any one of the
first four prevents the stack from starting.

### 2a. Every healthcheck called curl, which none of the images contain

```
/bin/sh: 1: curl: not found
```

Not in `qdrant/qdrant`, not in `ollama/ollama`, not in `python:3.10-slim`. All
three healthchecks used it, so all three services sat `unhealthy` permanently,
with a failing streak in the dozens.

Because `backend` waits on `condition: service_healthy` for both qdrant and
ollama, and `frontend` waits on `backend`, the entire dependency chain
deadlocked. No application container ever started. Qdrant was serving correctly
the whole time and returning HTTP 200 to the host, which is what makes this
failure mode nasty: the service is fine, the probe is wrong, and the symptom is
a stack that hangs rather than an error.

**Fix.** Probes now use only what each image actually contains: `bash` with
`/dev/tcp` for qdrant and ollama, and the Python interpreter for the backend.

**Lesson.** A healthcheck is code that runs in a different filesystem from the
one you tested in. Verify the probe binary exists in the target image.

### 2b. GPU reservation blocked every non-NVIDIA host

```
could not select device driver "nvidia" with capabilities: [[gpu]]
```

The `nvidia` device reservation was unconditional, with a comment telling the
operator to comment it out if they had no GPU. Docker fails the entire `up`, so
the stack refused to start on any machine without the NVIDIA container toolkit,
including all Apple Silicon.

A missing GPU should mean slower inference, not a stack that will not start.

**Fix.** Moved to `docker-compose.gpu.yml` as an opt-in overlay. The base file
runs Ollama on CPU everywhere.

### 2c. Frontend image could never have built

Two independent breakages:

- `frontend/Dockerfile` copies `.next/standalone`, which Next.js only emits when
  `output: "standalone"` is set. It was not set, so the directory never existed.
- The runner stage copies `/app/public`. That directory has never existed in this
  project; the app serves no static assets.

**Fix.** Set `output: "standalone"`; removed the `public` copy with a comment
recording how to restore it.

### 2d. No .dockerignore

The build context was the full 4.3 GB working tree. It included `qdrant_storage/`,
which holds the plaintext of every ingested document, and `storage/medcomply.db`.

Nothing had leaked, because nothing had been built. But the first successful
build would have shipped ingested document text inside a distributable image.

**Fix.** `.dockerignore` excluding the virtualenv, `node_modules`, all runtime
data, secrets, and logs. Verified after building: no `qdrant_storage`, no
database, no documents anywhere in the image, and `storage/` present but empty.

### 2e. Images built from source that is not in the public repo

`build: {context: ., dockerfile: backend/Dockerfile}` resolves against the
private source tree. In the documentation repo there is nothing to build.

**Fix.** Backend and frontend now pull published images from GHCR. Both packages
are **private**, verified through the API and by confirming an anonymous pull is
rejected with `unauthorized`. A Python image contains readable `.py` source, so
public packages would have published the implementation.

**Verified end state**, from a clean `docker compose down -v`: all four services
healthy in about 20 seconds, `/api/v1/meta/health` returning
`{"status":"ok","components":{"backend":"ok","vectorStore":"ok","ollama":"ok"}}`,
frontend HTTP 200, and service-to-service reachability confirmed from inside the
backend container.

---

## 3. Runtime data and the full dependency tree were committed to git

**Severity: high. Status: fixed.**

The source repository had no `.gitignore`. The initial commit captured 64,032
files: the Python virtualenv, `node_modules`, Next.js build output, compiled
bytecode, logs, the SQLite database, and a 236 MB Qdrant vector store.

Actual source is 443 files.

The vector store is the serious part. Its payloads contain the full plaintext of
every ingested chunk, so the corpus was sitting in version control. That corpus
is synthetic test material, verified by inspection, so nothing customer-owned was
committed. The mechanism, however, does not distinguish between test documents and
real ones.

**Contained by luck, not design.** That repository has no git remote and has
never been pushed. Nothing was exposed. Had it ever been pushed to the public
repo, the document corpus and the entire application source would have gone with
it.

**Fix.** A `.gitignore` covering vendored, generated, and runtime paths, and
`git rm --cached` for everything already tracked. Files stay on disk, so the
running system is unaffected.

**Still open.** The data remains in the initial commit's history. Untracking
stops it going forward; it does not remove the past. Acceptable only because that
repository is never pushed. If it is ever published, history must be purged
first.

---

## 4. Documentation claims drifted from the implementation

**Severity: medium. Status: fixed.**

Four architectural claims in the README were checked against the code. Three held
with corrections needed; one was partly unsupported.

- **Chunk sizes were stale.** Documented as 1800 chars with 300 overlap; the code
  uses a ~3000 char parent target, 4500 max, 1200 max child.
- **"Hash-verified" overstated.** Hashes are computed and stored correctly, but
  nothing recomputes and compares them.
- **"Can be replayed" was not implemented.** No replay path exists.
- **"LLM fallback second"** contradicted the sentence after it and made a true,
  stronger claim sound weaker. There is no LLM fallback deciding coverage.

**Why this matters more here than elsewhere.** The product's value is that its
claims about determinism and grounding are verifiable. A reviewer who finds one
claim unsupported has reason to doubt all of them, including the ones that are
true and load-bearing.

**Fix.** Claims corrected against the code, with limits stated explicitly rather
than removed quietly.

---

## Open items

| Item | Severity | Note |
|---|---|---|
| Snapshot hashes never re-verified | Medium | Provenance stamp, not tamper detection |
| Snapshot replay not implemented | Medium | Compare and export exist |
| Vector store in source repo history | Medium | Contained: repo has no remote and is never pushed |
| Snapshot immutability by convention | Low | Single write path, no constraint enforcing it |
| Deprecated FastAPI `regex=` parameter | Low | Breaks on a future FastAPI major |
| Scanned-document extraction unmeasured | Low | See [`06-evals.md`](06-evals.md) |
