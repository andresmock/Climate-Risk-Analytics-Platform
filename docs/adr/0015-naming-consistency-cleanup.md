# 15. Naming consistency cleanup: terraform-apply, ingestion-invoker, climate_risk_warehouse

## Status

Accepted

## Context

[ADR-0012](0012-terraform-apply-moves-local-only.md) revoked `terraform-ci`'s CI trust entirely —
it's now a human-impersonated, local-only identity — and flagged the resulting name mismatch as
"optional future cleanup," deferred because renaming it means recreating the service account
rather than a simple in-place edit.

Auditing naming project-wide surfaced two more instances of the same underlying bug. Every
identity and dataset in this repo is meant to be named for what it's trusted to do
(`ingestion-runtime`, `ingestion-deploy`, `dataform-runtime`, `climate_risk_raw`), not for who
invokes it or some other incidental fact. Three names broke that rule:

- `terraform-ci` — named for an invoking context (CI) that's no longer even true.
- `ingestion-scheduler` — reads as "the schedule," not "the identity Cloud Scheduler invokes the
  job as." The Terraform-internal label already got this right (`scheduler_invoker`); only the
  GCP-facing `account_id` didn't.
- The modelled-data BigQuery dataset — its siblings `climate_risk_raw` and `climate_risk_assertions`
  both carry a role suffix, but this one is bare `climate_risk`, even though its own Terraform
  label is `warehouse`.

## Decision

Rename all three:

- `terraform-ci` → `terraform-apply` (pairs with the existing read-only `terraform-plan`, and
  reuses the name the CI `terraform-apply` job itself had before ADR-0012 retired it). The custom
  role bound to it (ADR-0013) is renamed the same way: `terraform_ci` → `terraform_apply`.
- `ingestion-scheduler` → `ingestion-invoker`, matching the Terraform resource label it already
  had internally.
- BigQuery datasets `climate_risk` → `climate_risk_warehouse` and `climate_risk_assertions` →
  `climate_risk_warehouse_assertions`, so all three read as one family:
  raw / warehouse / warehouse_assertions. Dataform's `workflow_settings.yaml` and the two `.sqlx`
  files that hardcode a `schema` config are updated in the same change — Dataform resolves these
  independently of what Terraform manages, so a Terraform-only rename would have silently
  diverged from what Dataform actually writes to.

None of `terraform-ci`'s own identity, its custom-role binding, or the human operator's
impersonation grant are Terraform-managed (bootstrapped by hand since ADR-0004/0006, per
ADR-0013). Landing this rename therefore takes the same manual, out-of-band steps every other
change to that identity has: create the `terraform-apply` service account; bind the recreated
`terraform_apply` custom role to it (requires an identity with `roles/iam.roleAdmin` or
equivalent — not `terraform-ci`/`terraform-apply` itself, the same limitation that applied when
this custom role was first created); grant the human operator
`roles/iam.serviceAccountTokenCreator` on the new SA; apply this PR's Terraform changes while
still impersonating the old `terraform-ci` (still trusted, still holds the old role); then switch
local workflow to `terraform-apply` going forward. `ingestion-invoker` and the dataset renames are
ordinary Terraform-managed replacements, applied in the same run.

## Manual grants actually required (discovered during rollout)

The plan above assumed `terraform-ci`'s real permissions matched what `iam.tf`'s comments
documented. They didn't. Landing `terraform-apply` required mirroring three out-of-band grants
`terraform-ci` held that were never recorded anywhere in this repo:

- `roles/storage.objectAdmin` on the remote-state GCS bucket — without it, `terraform-plan`/
  `apply` can't even read `default.tfstate`. Found by inspecting `terraform-ci`'s actual bucket
  IAM policy (`gcloud storage buckets get-iam-policy`), since no ADR or comment named it.
- The `terraform_apply` custom role binding itself — expected (ADR-0013 already says this step is
  manual), but easy to skip since nothing else in this rollout depends on it visibly failing until
  the very first `plan`.
- `roles/iam.roleAdmin` — undocumented anywhere. The scoped custom role deliberately excludes
  `iam.roles.*` and `resourcemanager.projects.*` permissions (ADR-0013), which means it can't read
  or manage itself, and `data.google_project.current` (`iam.tf`) can't resolve the project number
  either. `terraform-ci` only worked because it separately held `roles/iam.roleAdmin`, granted at
  some point with no record of when or why. `iam.tf`'s "Manual grants" section now documents it.

Net effect: `terraform-ci`'s actual, complete permission set was always larger than what this
repo's Terraform and comments claimed. This rollout is what surfaced that gap; ADR-0013's premise
("exactly the permissions this repo's Terraform declares") was never fully true in practice.

## Consequences

- Every IAM identity and BigQuery dataset in this repo now follows one rule: name for role, never
  for invoking context.
- `climate_risk`/`climate_risk_assertions` are dropped and recreated under their new names — any
  already-materialized Dataform output is lost until the next scheduled run repopulates it.
  Acceptable: it's derived, rebuildable output, not source data — the raw GCS objects and
  `climate_risk_raw` external table are untouched.
- Hit this directly during rollout: `terraform apply` refused to replace the non-empty
  `warehouse`/`warehouse_assertions` datasets (`resourceInUse`), requiring a manual `bq rm -r -f`
  before it could proceed. Fixed going forward by adding `delete_contents_on_destroy = true` to
  both — deliberate, since (unlike `raw`, which keeps `force_destroy = false`) their contents are
  Dataform-rebuildable.
- `terraform-ci` exists as a live, still-privileged, fully unused identity until manually deleted
  post-transition — the same pattern ADR-0012 already established for retiring trust without
  immediately tearing down the identity behind it.
- ADRs before this one refer to `terraform-ci`, `ingestion-scheduler`, and `climate_risk` by the
  names that were current when they were written. Left as-is: this repo treats ADRs as
  point-in-time records, not living docs.
