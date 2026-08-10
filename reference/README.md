# Reference deployment topology

These files are **illustrative, not runnable from this repository.**

MedComplyAI is closed source. This repository publishes architecture and
deployment documentation, not the application. The files here show how the
deployed system is actually composed, so that the topology, service
boundaries, ports, volumes, and health checks can be reviewed without access
to the source tree.

## Why they will not build here

`reference/docker-compose.yml` builds the backend and frontend images from
source:

```yaml
backend:
  build:
    context: .
    dockerfile: backend/Dockerfile
```

The build context is the root of the **private** source repository, which
contains `backend/requirements.txt`, `backend/app/`, and `frontend/`. None of
that is present here, so an image build cannot resolve its `COPY` paths.

The `COPY` paths in the Dockerfiles are correct for that context. They are
left unmodified on purpose. Rewriting them to resolve against this repository
would break them for the deployment they actually describe.

## File map

| File | Corresponding path in the private source repo |
|---|---|
| `docker-compose.yml` | `docker-compose.yml` |
| `docker-compose.observability.yml` | `docker-compose.observability.yml` |
| `backend.Dockerfile` | `backend/Dockerfile` |
| `frontend.Dockerfile` | `frontend/Dockerfile` |

The Dockerfiles are renamed here only to keep this directory flat. In the
source repo they sit inside `backend/` and `frontend/`, which is what the
compose `dockerfile:` keys refer to.

## What is worth reading here

- **Service topology.** Four core services: Qdrant for vectors, Ollama for
  local inference, the FastAPI backend, and the Next.js frontend. No cloud
  inference endpoint appears anywhere in the stack, which is the constraint
  the product exists to satisfy.
- **Health check dependencies.** The backend waits for Qdrant and Ollama to
  report healthy, and the frontend waits for the backend. Ollama is given a
  30 second start period because model loading is slow on first boot.
- **Secret handling.** `docker-compose.observability.yml` refuses to start
  when its secrets are unset or empty, rather than falling back to defaults.
  See `docs/05-failure-modes.md` for what this looked like before it was
  fixed, and why the fix required splitting the file.
- **GPU reservation.** The Ollama service reserves an NVIDIA device. On hosts
  without a GPU that block must be commented out. See the deployment
  requirements in the root README.
