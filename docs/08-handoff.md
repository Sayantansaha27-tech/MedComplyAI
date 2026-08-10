# Handoff

What a customer administrator needs in order to run this without the person who
built it. Written for someone competent with Docker who has never seen this
system.

## What you are operating

Four containers on one host. Nothing calls out to the internet at inference time.
All customer data stays in local volumes.

| Service | Port | Role |
|---|---|---|
| frontend | 3000 | Web UI, the only thing users open |
| backend | 8000 | API and all logic |
| qdrant | 6333 | Vector store, holds document text |
| ollama | 11434 | Local model inference |

If you learn one command, learn this one:

```bash
curl http://localhost:8000/api/v1/meta/health
```

`{"status":"ok","components":{"backend":"ok","vectorStore":"ok","ollama":"ok"}}`
means the system is fine. Anything else tells you which of the three is not.

## Your responsibilities

1. **Backups.** Nothing is backed up automatically. See
   [`07-runbook.md`](07-runbook.md). If you do one thing on a schedule, do this.
2. **Disk.** The vector store grows with every ingested document, and models are
   ~7.7 GB. Alert at 80%.
3. **Upgrades.** Manual, and you decide when. Always check
   `indexSchemaVersion`; a change means reindexing.
4. **Access control.** See the security boundary below. This is the one that is
   easy to get wrong.

## The security boundary

**Read this carefully. It is the most likely thing to be misconfigured.**

The application has **no user authentication and no role-based access control**.
Anyone who can reach port 3000 can use the system, read every ingested document,
and run every analysis.

This is deliberate. It is a single-tenant on-premise install where the deployment
boundary is the security boundary. It is not a defect, but it does mean:

- **Do not expose ports 3000 or 8000 to the public internet.** Ever.
- Bind to a private interface or put it behind your own authenticating reverse
  proxy or VPN.
- Anyone with host access can read every document in the system.

`GAP_API_KEY` adds a shared-secret check on gap endpoints only. It is not user
authentication and does not protect the UI.

### Where customer document text lives

Four places, all needing the same handling rules as the source dossiers:

| Location | What is in it |
|---|---|
| `reference_qdrant_data` volume | Full plaintext of every ingested chunk |
| `reference_backend_storage` volume | Uploads, database, snapshots |
| Your backup archives | Copies of both of the above |
| Langfuse, if enabled | Prompts, evidence spans, model outputs |

Backups are the one people forget. A tarball of the vector store is a copy of
every customer document in the system, and it usually ends up somewhere with
weaker access control than the server.

## Routine operations

```bash
cd MedComplyAI/reference

docker compose ps                      # what is running
docker compose logs -f backend         # follow backend logs
docker compose restart backend         # restart one service
docker compose down                    # stop, KEEPS data
docker compose up -d                   # start
```

**`docker compose down -v` destroys all data.** The `-v` deletes the volumes,
including the vector store and database. There is no undo. Do not use it on a
production host.

## When users report problems

Work in this order. Most reports resolve in the first two steps.

1. `curl http://localhost:8000/api/v1/meta/health` — which component is unwell?
2. `docker compose ps` — is anything restarting or unhealthy?
3. `docker compose logs --tail 100 backend`
4. Match the symptom against the triage section of
   [`07-runbook.md`](07-runbook.md).

Two things that look like bugs and are not:

- **"The AI said it could not produce a grounded response."** Correct behaviour.
  The model could not cite evidence that actually exists, so the answer was
  discarded rather than shown with a fabricated citation. Frequent occurrences
  point at retrieval, usually a document that was never ingested.
- **"The observability stack will not start."** It refuses without its three
  secrets, by design, rather than falling back to defaults.

## What you cannot fix, and who to call

You can restart, restore, upgrade, roll back, and reindex. You cannot change how
the system decides anything, and you should not try.

Escalate for:

- **Wrong coverage results.** The classifiers are code. Adding or correcting a
  requirement rule is a development change and a new release.
- **A new framework.** Not configuration. Each framework needs a hand-written
  evaluator, per [ADR-002](03-decisions.md).
- **`indexSchemaVersion` changed and reindexing fails.**
- **Anything suggesting document text left the host.** Treat as an incident.
  Nothing in the design permits it, so an apparent case means something is
  seriously wrong.

## Known limitations, so they do not surprise you

Stated so you can answer users without escalating:

- **Snapshot replay does not exist.** Runs can be compared and exported, not
  re-executed to reproduce a historical result.
- **Snapshot hashes are not verified.** They are a provenance stamp binding an
  explanation to an engine state, not tamper detection. Do not present them to an
  auditor as proof a record is unaltered.
- **Classifier accuracy is not measured.** The system is reproducible; its
  precision and recall against expert ground truth are unquantified. See
  [`06-evals.md`](06-evals.md).
- **Scanned document quality is not guaranteed.** Prefer native PDF or DOCX.
- **One concurrent run per tenant by default.**

## The one-paragraph version

Four containers on one host, no internet access at inference, all data in local
volumes. Health check tells you what is wrong. Back up the two data volumes on a
schedule and guard the backups like the documents themselves, because that is what
they are. Never expose it to the internet, because there is no login. Never run
`down -v`. Escalate anything about how it decides; handle anything about whether
it is running.
