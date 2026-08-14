# 4. Terraform plan/apply in CI

Date: 2026-08-14

## Status

Accepted

## Context

[ADR-0003](0003-engineering-workflow-and-ci.md) deferred live `terraform plan`/`apply` in CI until a real GCP project existed, noting it would be "added to CI at that point rather than faked now." That project now exists — remote GCS state, the required APIs, the raw bucket, and the BigQuery warehouse datasets are all live (see `terraform/README.md`).

In the interim, applies were run by hand, locally, against `terraform.tfvars`/`backend.hcl`. That meant infrastructure changes landed before the corresponding PR was reviewed or merged: PR review had no real change left to evaluate, and `main` could silently drift from whatever was actually live if a PR were amended or abandoned after the local apply.

## Decision

**Authentication:** CI authenticates to GCP via Workload Identity Federation, not a stored service account key. GitHub Actions exchanges a short-lived OIDC token for GCP credentials by impersonating a dedicated `terraform-ci` service account; the workload identity pool's attribute condition restricts this to workflows running in this repo. The service account's IAM roles are scoped to what Terraform actually manages today (`storage.admin`, `bigquery.admin`, `serviceusage.serviceUsageAdmin`) and will need extending as new resource types are declared (e.g. IAM-admin roles once a Cloud Run runtime service account is added).

**CI jobs** (`.github/workflows/ci.yml`):
- `terraform-plan` runs on every PR, authenticates via WIF, and posts `terraform plan`'s output as a PR comment (updating the same comment on subsequent pushes rather than piling up new ones). Review now happens against the actual planned infra change, not just the `.tf` source diff.
- `terraform-apply` applies the same way, but only on `main` and only via manual `workflow_dispatch` — merging a PR does not by itself trigger it.

**Why manual dispatch instead of auto-apply-on-merge:** the standard pattern gates the apply job behind a GitHub Environment with a required-reviewer protection rule, so merging is not itself the final destructive action. That protection rule is not available for private repositories on GitHub's free tier. A manual trigger is the interim substitute checkpoint: the `terraform-apply` environment restricts execution to `main`, but the human-in-the-loop step is choosing to click "Run workflow," not an enforced review gate. Once the repo goes public — tied to the ingestion-to-BigQuery milestone from ADR-0003, not to this decision — the required-reviewer rule becomes available and should replace manual dispatch with auto-apply-on-merge gated by that rule.

**Local `terraform apply` is retired.** CI is now the only place applies happen. `terraform.tfvars`/`backend.hcl` remain locally (gitignored, as before) for `plan`/`validate` while iterating, but are no longer used to apply.

## Consequences

- PR review evaluates the real planned infrastructure change; `main` and live state can no longer drift from an unreviewed local apply.
- The apply step still requires a manual click after merge — this is a checkpoint of convenience, not an access-controlled gate. Anyone with write access to the repo could dispatch it; the actual constraint is the `main`-only branch restriction on the `terraform-apply` environment.
- Follow-up, once the repo goes public: add a required-reviewer rule to the `terraform-apply` environment and switch its trigger from `workflow_dispatch` back to `push` on `main`.
- The service account's granted roles need to be revisited each time Terraform starts managing a new class of resource (e.g. IAM bindings, Artifact Registry, Cloud Run) — they are deliberately not broad grants made in advance of need.
