# Runbook

Operational procedures for a deployed instance. Assumes the stack in
[`reference/`](../reference/).

## Install

```bash
git clone https://github.com/Sayantansaha27-tech/MedComplyAI.git
cd MedComplyAI/reference

gh auth token | docker login ghcr.io -u <your-github-user> --password-stdin
cp ../.env.example .env
docker compose up -d
```

Wait for health, then pull models. Ollama starts empty and nothing works until
they are present.

```bash
docker exec medcomplyai-ollama ollama pull qwen2.5:7b-instruct
docker exec medcomplyai-ollama ollama pull rjmalagon/gte-qwen2-1.5b-instruct-embed-f16
docker exec medcomplyai-ollama ollama pull qwen3-vl:2b-thinking   # optional, scanned PDFs
```

Roughly 7.7 GB total. Verify:

```bash
curl http://localhost:8000/api/v1/meta/health
docker exec medcomplyai-ollama ollama list
```

Expect `"status":"ok"` with all three components `ok`.

### With a GPU

```bash
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
docker compose exec ollama nvidia-smi   # confirm the GPU is visible
```

Requires the NVIDIA container toolkit on the host. Without it the GPU overlay
fails the whole `up`, which is why it is not in the base file.

## Upgrade

```bash
cd MedComplyAI/reference
git pull

# Back up first, see below
docker compose pull
docker compose up -d
```

Check `indexSchemaVersion` in `/api/v1/meta/version` before and after. **If it
changed, the vector store must be reindexed.** Documents indexed under the old
schema will retrieve incorrectly or not at all.

```bash
# after an indexSchemaVersion change
docker compose exec backend python -m app.scripts.reindex   # verify script name for your version
```

Model IDs are also reported in `/meta/version`. A model change alters output even
with no code change, which matters if you are reproducing a historical result.

## Rollback

Images are tagged by version, so rollback is a tag change.

```bash
cd MedComplyAI/reference
# pin the previous tag in docker-compose.yml, then
docker compose up -d
```

**Rollback is safe only if `indexSchemaVersion` did not change.** If it did, roll
the data back too, from the backup taken before the upgrade. An old binary against
a new index is the failure mode that produces silently wrong retrieval rather than
an error.

## Backup

All state lives in three named volumes. `docker compose down` preserves them;
`down -v` destroys them.

| Volume | Contents |
|---|---|
| `reference_qdrant_data` | Vector store, includes ingested document text |
| `reference_backend_storage` | SQLite database, uploads, snapshots |
| `reference_ollama_data` | Pulled models, re-pullable, low value |

```bash
# Stop writes first for a consistent copy
docker compose stop backend

docker run --rm \
  -v reference_qdrant_data:/data:ro \
  -v "$PWD/backups:/backup" \
  alpine tar czf /backup/qdrant-$(date +%F).tar.gz -C /data .

docker run --rm \
  -v reference_backend_storage:/data:ro \
  -v "$PWD/backups:/backup" \
  alpine tar czf /backup/storage-$(date +%F).tar.gz -C /data .

docker compose start backend
```

**These backups contain customer document text.** Treat them with the same
handling rules as the source dossiers: encrypted at rest, access controlled, and
never copied to a machine outside the customer environment.

Restore reverses the direction, with the stack down.

## Triage

### Everything reports unhealthy and nothing starts

Check the healthcheck output rather than assuming the service is down:

```bash
docker inspect medcomplyai-qdrant --format '{{json .State.Health}}'
```

If it shows `curl: not found`, the compose file predates the healthcheck fix. The
service is fine and the probe is wrong. See
[`05-failure-modes.md`](05-failure-modes.md).

### `could not select device driver "nvidia"`

The GPU overlay is in use on a host without the NVIDIA container toolkit. Drop the
`-f docker-compose.gpu.yml` and run on CPU, or install the toolkit.

### Backend up but `vectorStore` or `ollama` reports not ok

```bash
docker compose ps
docker compose logs qdrant --tail 50
docker compose exec backend python -c "import urllib.request; print(urllib.request.urlopen('http://qdrant:6333/').status)"
```

Service names resolve on the compose network. `localhost` from inside the backend
container is the backend, not the dependency, which is a common misdiagnosis.

### Analyses fail with model errors

Confirm the models are actually pulled:

```bash
docker exec medcomplyai-ollama ollama list
```

An empty list is the usual cause after a fresh install or after `down -v`, which
destroys `ollama_data`.

### Runs rejected with 409

Concurrency cap reached. Default is 1 per tenant via
`GAP_MAX_CONCURRENT_RUNS_PER_TENANT`. Either wait, or raise it if the host has
headroom. Raising it on a CPU-only host will make every run slower.

### Observability stack refuses to start

```
required variable LANGFUSE_NEXTAUTH_SECRET is missing a value
```

Working as designed. Set all three secrets; it will not fall back to defaults.

```bash
openssl rand -base64 32   # once per variable
```

### Ungrounded response fallbacks

```json
{"is_fallback": true, "message": "AI could not produce a grounded response"}
```

Not an error. The model could not produce output citing evidence that exists, so
the gateway discarded it. Frequent occurrences usually mean retrieval returned
poor context, so check that the relevant document was ingested and that
`indexSchemaVersion` matches.

## Logs

```bash
docker compose logs -f backend
docker compose logs --tail 100 qdrant
```

Backend logs include grounding outcomes per LLM interaction. With the
observability overlay running, full traces are at `http://localhost:3030`.

**Traces contain prompts, retrieved evidence spans, and model outputs**, which
means they contain customer document text. The Langfuse instance is as sensitive
as the vector store and should be access-controlled accordingly.
