# terraform

Infrastructure as code for the platform's GCP resources (see
[docs/adr/0002](../docs/adr/0002-initial-architecture-and-technology-stack.md)).

A real GCP project now backs this config, with state stored remotely in GCS, the required APIs
(`apis.tf`) declared, the raw landing bucket (`storage.tf`), and the BigQuery datasets
(`bigquery.tf`): `climate_risk_raw` is an external table reading the raw GCS objects directly (no
copy, no separate load step — BigQuery just queries them where they sit), and
`climate_risk_warehouse` is where Dataform will materialize modelled output on top of it.

Ingestion runs as two Cloud Run Jobs from the same image (`cloud_run.tf`): `ingestion` pulls
forecasts every 6 hours, and `ingestion-historical` pulls historical weather daily
([ADR-0016](../docs/adr/0016-historical-weather-ingestion.md)). Both are triggered by Cloud
Scheduler (`scheduler.tf`) via the Cloud Run Jobs Admin API. The image lives in Artifact Registry
(`artifact_registry.tf`). Three narrowly-scoped service accounts (`iam.tf`) support this, shared
by both jobs: `ingestion-runtime` (what the jobs execute as), `ingestion-deploy` (CI's identity
for pushing images and updating the jobs — kept separate from `terraform-apply`, which never
touches the live image), and `ingestion-invoker` (Cloud Scheduler's invoker identity). See
[ADR-0005](../docs/adr/0005-ingestion-scheduling-and-deploys.md) for why deploys are decoupled
from `terraform apply` this way.

## Applying changes

`terraform apply` against the real project is local-only, run by a human (see
[docs/adr/0012](../docs/adr/0012-terraform-apply-moves-local-only.md)):

- Every PR touching `terraform/` runs `terraform plan` in CI and posts the output as a PR
  comment, so review covers the actual planned infra change. CI never runs `apply`.
- After merging to `main`, apply the change yourself, locally, impersonating `terraform-apply`:

  ```bash
  cd terraform
  export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT="terraform-apply@<PROJECT_ID>.iam.gserviceaccount.com"
  terraform init -backend-config=backend.hcl
  terraform plan -out=tfplan
  terraform apply tfplan
  ```

  This requires your own GCP principal to hold `roles/iam.serviceAccountTokenCreator` on
  `terraform-apply` (granted by hand, same as `terraform-apply`'s other roles — see
  [docs/adr/0013](../docs/adr/0013-terraform-ci-custom-role.md)).
- A scheduled drift check (`.github/workflows/terraform-drift.yml`) runs `terraform plan` daily
  against `main` and fails if it finds unapplied changes, so a merge that never got applied
  doesn't go unnoticed — see [docs/adr/0014](../docs/adr/0014-terraform-drift-detection.md).

Two gitignored files are needed for local `init`/`plan`/`apply` (neither is committed — see
`.gitignore`):

- `terraform.tfvars` — sets `project_id` (and other required vars) to the real values
- `backend.hcl` — sets the `bucket`/`prefix` for the remote state backend, passed via
  `terraform init -backend-config=backend.hcl`

Without them, `terraform validate` still works (no live project/credentials needed), but
`init`/`plan`/`apply` will fail or fall back to asking for the backend config interactively.
