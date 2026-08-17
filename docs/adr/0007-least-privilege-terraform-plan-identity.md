# 7. Least-privilege identity for terraform plan in CI

Date: 2026-08-17

## Status

Accepted

## Context

[ADR-0004](0004-terraform-plan-apply-in-ci.md) split `terraform plan` and `terraform apply` into
separate CI jobs and gave `terraform-apply` a human-approval checkpoint (a required reviewer on
the `terraform-apply` environment). `terraform-plan` was left running automatically on every
same-repo pull request, with no such gate, on the reasoning that plan is read-only.

Both jobs authenticate as the same `terraform-ci` service account, whose project-level roles
(`storage.admin`, `bigquery.admin`, `serviceusage.serviceUsageAdmin`, plus the resource-specific
grants in `iam.tf`) exist so that `terraform-apply` can actually create/modify/destroy project
resources. `terraform init`/`plan` executes provider code and evaluates data sources with
whatever ambient credentials the job holds — it isn't sandboxed to read-only API calls just
because the Terraform command is `plan`. A same-repo PR (from a compromised collaborator
account, or a malicious `required_providers` source) therefore reaches `terraform-ci`'s full
write-level blast radius before any human reviews it, which defeats the point of gating
`terraform-apply` behind a reviewer: the reviewer only ever sees the destructive path, not the
already-privileged one.

## Decision

Give `terraform-plan` its own service account, distinct from `terraform-ci`:

- **`terraform-plan`** (`terraform/iam.tf`): created via Terraform, same as `ingestion-deploy`,
  with a `roles/iam.workloadIdentityUser` binding to the same GitHub Actions WIF pool/repo
  condition already trusted for `terraform-ci` and `ingestion-deploy`.
- **Project-level role:** `roles/viewer`, granted by hand (`gcloud projects
  add-iam-policy-binding`), the same way `terraform-ci`'s own project roles are granted by hand
  rather than through this repo's Terraform — this repo doesn't manage either. Viewer covers
  read/diff access across resource types as Terraform starts managing new ones, without needing
  per-resource-type grants extended over time the way `terraform-ci`'s roles are.
- **State bucket access:** two conditional IAM bindings on just the state bucket, granted by
  hand, instead of a single unconditional `roles/storage.objectAdmin`:
  - `roles/storage.objectViewer`, unconditional — read access to every object in the bucket,
    including the real `.tfstate` object `plan` needs to diff against.
  - `roles/storage.objectAdmin`, with an IAM condition restricting it to objects matching
    `resource.name.endsWith(".tflock")` — create/delete rights scoped to only the GCS backend's
    lock file, not the state object itself.

  The GCS backend's locking mechanism needs create/delete on that lock object, not just read —
  `objectViewer` alone isn't enough for `plan` to succeed. A flat `objectAdmin` grant on the
  bucket would technically work too, but it would let an unreviewed PR's `plan` run overwrite or
  delete the live `.tfstate` object itself, not just take the lock — a real (if narrower) blast
  radius left over from the identity split this ADR is meant to close. The two-binding form closes
  that gap: `terraform-plan` can read state and take/release the lock, but cannot touch the state
  object's contents.
- **Verify before switching CI over:** `roles/viewer` is broad but is documented to exclude most
  `getIamPolicy` calls across services, including IAM. Every `google_service_account_iam_member`
  resource in `iam.tf` (four, as of this ADR) requires `plan` to call `GetIamPolicy` on the target
  service account to refresh state before diffing. Before pointing `ci.yml` at `terraform-plan`,
  smoke-test this directly:
  ```
  gcloud iam service-accounts get-iam-policy ingestion-runtime@<PROJECT_ID>.iam.gserviceaccount.com \
    --impersonate-service-account=terraform-plan@<PROJECT_ID>.iam.gserviceaccount.com
  ```
  If this fails on a permission error, `roles/viewer` doesn't cover it — the likely fix is adding
  `roles/iam.securityReviewer` (a read-only role covering `getIamPolicy` across most resource
  types), not broadening `terraform-plan` back toward write access. Confirm this before the
  `ci.yml` switch, not after — a `plan` job that silently starts failing project-wide is a worse
  rollout than catching it here.

`.github/workflows/ci.yml`'s `terraform-plan` job switches to this identity once it exists, is
provisioned in GCP, and passes the smoke test above — the service account has to exist (and work)
before CI can be pointed at it, so this lands as a separate, later change rather than in the same
PR that creates the account.

## Consequences

- An unreviewed same-repo PR can now only read project state via `terraform-plan`'s identity, not
  create, modify, or delete anything — the `terraform-apply` reviewer gate is once again the
  actual checkpoint before any write happens.
- Two identities to keep in sync with reality instead of one: as Terraform starts managing new
  resource types, `terraform-ci` needs its write-level roles extended (already true per
  ADR-0004) and `terraform-plan` needs equivalent read coverage — `roles/viewer` should already
  cover most of that automatically, but IAM-policy reads and bucket- or resource-specific state
  access may not (see the smoke test above; `roles/iam.securityReviewer` may need adding
  alongside `roles/viewer` for the four `google_service_account_iam_member` resources).
- `terraform-plan` can still create/delete the state bucket's lock object and read (but not
  write) the `.tfstate` object itself. That's a real, if narrow, residual capability — an
  unreviewed PR's `plan` run could theoretically hold the lock open (denial-of-service on future
  applies) but cannot corrupt or exfiltrate-via-overwrite the state contents.
- `terraform-plan`'s project role and both state-bucket grants are manual, out-of-band steps,
  same as `terraform-ci`'s bootstrap — not visible in this repo's Terraform config.
