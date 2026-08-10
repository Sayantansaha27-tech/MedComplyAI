# Reference deployment

MedComplyAI is closed source. This repository publishes architecture and
deployment documentation, not the application.

The stack here does run, with one constraint: `qdrant` and `ollama` are public
images and start for anyone, while `backend` and `frontend` are published as
**private** images and need registry access.

## Running it

```bash
# 1. Authenticate to the container registry (needed for backend + frontend)
gh auth token | docker login ghcr.io -u <your-github-user> --password-stdin

# 2. Configuration
cp ../.env.example .env

# 3. Start
docker compose up -d
```

Expect all four services healthy in about 20 seconds:

```
SERVICE    STATUS
backend    Up (healthy)
frontend   Up
ollama     Up (healthy)
qdrant     Up (healthy)
```

Verify:

```bash
curl http://localhost:8000/api/v1/meta/health
open http://localhost:3000
```

Without the `docker login` step, qdrant and ollama start and the backend and
frontend fail to pull. That is expected, not a broken compose file.

Models are not baked into the images. Ollama starts empty, so pull the three
models before running an analysis. See the deployment requirements in the root
README.

## Overlays

The base file runs everywhere. Two opt-in overlays add capability:

```bash
# NVIDIA GPU acceleration for Ollama
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d

# Langfuse LLM observability
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
```

Both are separate files rather than compose profiles, for reasons that cost
real debugging time and are worth stating.

**GPU.** An `nvidia` device reservation in the base file does not degrade
gracefully. Docker fails the whole `up` with `could not select device driver
"nvidia"` on any host without the NVIDIA container toolkit, including every
Apple Silicon machine. A missing GPU should mean slower inference, not a stack
that will not start.

**Observability.** Compose interpolates the entire file before it filters by
profile. A required-variable check on a profiled service therefore breaks the
core stack even when that profile is inactive. Keeping Langfuse in its own file
lets its secrets be mandatory without making them mandatory for everyone.

## Healthchecks do not use curl

Every healthcheck here avoids `curl`, which is not obvious and is deliberate.
None of the `qdrant`, `ollama`, or `python:3.10-slim` images ship it. The
original healthchecks all called `curl`, so all three services stayed
`unhealthy` forever, and because `backend` waits on
`condition: service_healthy`, the stack deadlocked before the backend ever
started.

The replacements use only what each image actually contains: `bash` and
`/dev/tcp` for qdrant and ollama, and the Python interpreter for the backend.

## Images

| Service | Image | Visibility |
|---|---|---|
| backend | `ghcr.io/sayantansaha27-tech/medcomplyai-backend:0.1.0` | private |
| frontend | `ghcr.io/sayantansaha27-tech/medcomplyai-frontend:0.1.0` | private |
| qdrant | `qdrant/qdrant:v1.9.2` | public upstream |
| ollama | `ollama/ollama:latest` | public upstream |

The application images are private on purpose. A Python application image
contains readable `.py` source, so publishing them publicly would publish the
source. Private images keep the deployment reproducible for licensed
deployments without giving away the implementation.

The images carry no data. No vector store, no database, no ingested documents.
`storage/` exists inside the backend image but is empty, and all state lives in
named volumes created at first run.

## What is worth reading here

- **No cloud inference endpoint appears anywhere in the stack.** That is the
  constraint the product exists to satisfy, and it is visible in the topology
  rather than only asserted in prose.
- **Startup ordering is explicit.** The backend waits for qdrant and ollama to
  report healthy, the frontend waits for the backend. Ollama gets a 30 second
  start period because first-boot model loading is slow.
- **State is in named volumes**, not bind mounts, so a `docker compose down`
  without `-v` preserves the vector store and database.

See `docs/05-failure-modes.md` for the full account of what was broken here and
how it was found.
