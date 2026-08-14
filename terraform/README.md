# terraform

Infrastructure as code for the platform's GCP resources (see
[docs/adr/0002](../docs/adr/0002-initial-architecture-and-technology-stack.md)).

A real GCP project now backs this config, with state stored remotely in GCS, the required APIs
(`apis.tf`) declared, the raw landing bucket (`storage.tf`), and the BigQuery datasets
(`bigquery.tf`): `climate_risk_raw` is an external table reading the raw GCS objects directly (no
copy, no separate load step — BigQuery just queries them where they sit), and `climate_risk` is
where Dataform will materialize modelled output on top of it. The Cloud Run service, Cloud
Scheduler job, Artifact Registry repository, and IAM are not declared yet — those land once the
ingestion service has a real entrypoint to deploy (see `src/ingestion/README.md`).

## Applying changes

`terraform apply` against the real project happens in CI, not locally (see
[docs/adr/0004](../docs/adr/0004-terraform-plan-apply-in-ci.md)):

- Every PR touching `terraform/` runs `terraform plan` and posts the output as a PR comment, so
  review covers the actual planned infra change.
- After merging to `main`, apply is triggered manually from the Actions tab
  (`workflow_dispatch` on the `terraform-apply` job) rather than running automatically.

Local `terraform apply` is retired. To `init`/`plan`/`validate` locally while iterating, two
gitignored files are still needed (neither is committed — see `.gitignore`):

- `terraform.tfvars` — sets `project_id` to the real GCP project ID
- `backend.hcl` — sets the `bucket`/`prefix` for the remote state backend, passed via
  `terraform init -backend-config=backend.hcl`

Without them, `terraform validate` still works (no live project/credentials needed), but
`init`/`plan` will fail or fall back to asking for the backend config interactively.
