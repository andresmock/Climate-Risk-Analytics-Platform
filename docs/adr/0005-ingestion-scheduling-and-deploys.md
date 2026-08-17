# 5. Ingestion scheduling and deploys

Date: 2026-08-17

## Status

Accepted

## Context

The first milestone (ingestion writing to GCS, queryable in BigQuery via `climate_risk_raw.forecasts`) is complete, but `src/ingestion/` only runs manually today — no Cloud Run resource, Cloud Scheduler job, Artifact Registry repository, or IAM exists yet to run it in GCP (see `src/ingestion/README.md`, `terraform/README.md`). This ADR settles three things needed to close that gap: what kind of Cloud Run resource this is, how it gets triggered on a schedule, and how a new ingestion image reaches production without every code change forcing a manual step.

That last point matters because of [ADR-0004](0004-terraform-plan-apply-in-ci.md): `terraform apply` against the real project only runs via manual `workflow_dispatch`, as a deliberate human checkpoint before infrastructure changes take effect. If deploying new ingestion code meant bumping an image tag in Terraform, every ingestion code change — however small — would be gated behind that same manual click, coupling app-deploy frequency to an infra-apply ritual meant for a different kind of change.

## Decision

**Cloud Run Job, not Service.** `main.py` runs the ingestion loop once and exits (`sys.exit(run())`) — it's a batch script, not an HTTP server. A `google_cloud_run_v2_job` matches that run-to-completion shape directly; a Service would require Scheduler to hit an HTTP endpoint and the app to handle that request/response cycle for no reason.

**Cloud Scheduler triggers it via the Cloud Run Jobs API**, not an HTTP endpoint the app defines. A Cloud Scheduler job calls the Jobs API's `run` method for the ingestion job, authenticated with an OIDC token from a narrowly-scoped invoker service account. Cadence starts at every 6 hours (`0 */6 * * *`), matching typical forecast-update frequency without over-polling Open-Meteo's free API; this is a starting guess, not a measured choice, and is a one-line change to revisit once real cost/staleness data exists.

**Deploys are decoupled from `terraform apply`.** Terraform declares the Cloud Run Job's shape — initial image, CPU/memory, timeout, retries, runtime service account — but carries a `lifecycle { ignore_changes = [...] }` on the container image field, so Terraform stops managing that one attribute after creation. On every merge to `main` that touches `src/ingestion/` or its `Dockerfile`, a CI step builds the image, pushes it to Artifact Registry, and runs `gcloud run jobs update --image=...` directly against the live job — independent of the `terraform-apply` manual-dispatch gate. Infra-shape changes (resource limits, schedule, IAM) still go through the existing plan/PR-comment/manual-apply flow; only the image pointer bypasses it.

**New, narrowly-scoped service accounts** (continuing the least-privilege pattern from ADR-0004 — no broad grants ahead of need):
- `ingestion-runtime`: what the Cloud Run Job executes as; write access to the raw GCS bucket only.
- `ingestion-deploy` (WIF-based, used by CI): push access to the Artifact Registry repo and update access to the one ingestion Cloud Run Job. Kept separate from `terraform-ci`, which continues to manage infra shape only, not deploys.
- A scheduler-invoker identity, permitted only to execute the ingestion job.

## Consequences

- Ingestion code changes ship automatically on merge to `main`, without a manual "Run workflow" click — faster iteration than routing through ADR-0004's checkpoint. This trades away that checkpoint for app deploys specifically; acceptable because a bad ingestion deploy fails or writes bad data to GCS (recoverable, inspectable, non-destructive) rather than mutating cloud infrastructure the way a bad `terraform apply` could.
- Terraform's recorded image reference will permanently diverge from the live one after the first CI deploy. `ignore_changes` is required, not optional — without it, the next `terraform apply` would silently revert the job to its initial image, undoing the latest deploy.
- Two more service accounts to provision and reason about, each intentionally narrow rather than reusing `terraform-ci`.
- `terraform-ci`'s IAM roles need extending again (ADR-0004 anticipated this) to manage Artifact Registry and Cloud Run resources and to create the two new service accounts.
- The 6-hour cadence, and the CPU/memory/timeout/retry values for the job, are initial defaults rather than tuned settings — expect follow-up adjustments once the job has run for a while.
