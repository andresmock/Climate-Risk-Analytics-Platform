# terraform

Infrastructure as code for the platform's GCP resources (see
[docs/adr/0002](../docs/adr/0002-initial-architecture-and-technology-stack.md)).

A real GCP project now backs this config, with state stored remotely in GCS, the required APIs
(`apis.tf`) declared, the raw landing bucket (`storage.tf`), and the BigQuery datasets
(`bigquery.tf`): `climate_risk_raw` is an external table reading the raw GCS objects directly (no
copy, no separate load step — BigQuery just queries them where they sit), and `climate_risk` is
where Dataform will materialize modelled output on top of it.

Ingestion runs as a Cloud Run Job (`cloud_run.tf`), triggered every 6 hours by Cloud Scheduler
(`scheduler.tf`) via the Cloud Run Jobs Admin API. Its image lives in Artifact Registry
(`artifact_registry.tf`). Three narrowly-scoped service accounts (`iam.tf`) support this:
`ingestion-runtime` (what the job executes as), `ingestion-deploy` (CI's identity for pushing
images and updating the job — kept separate from `terraform-ci`, which never touches the live
image), and `ingestion-scheduler` (Cloud Scheduler's invoker identity). See
[ADR-0005](../docs/adr/0005-ingestion-scheduling-and-deploys.md) for why deploys are decoupled
from `terraform apply` this way.

### One-time manual setup

Two things need doing by hand before this applies cleanly — both are bootstrap steps outside
Terraform's own permissions, same as `terraform-ci`'s original setup:

1. **Extend `terraform-ci`'s IAM roles** to manage the new resource types (Artifact Registry,
   Cloud Run, and creating the new service accounts):
   ```
   gcloud projects add-iam-policy-binding <project> \
     --member="serviceAccount:terraform-ci@<project>.iam.gserviceaccount.com" \
     --role="roles/artifactregistry.admin"
   gcloud projects add-iam-policy-binding <project> \
     --member="serviceAccount:terraform-ci@<project>.iam.gserviceaccount.com" \
     --role="roles/run.admin"
   gcloud projects add-iam-policy-binding <project> \
     --member="serviceAccount:terraform-ci@<project>.iam.gserviceaccount.com" \
     --role="roles/iam.serviceAccountAdmin"
   ```
2. **Supply `github_actions_wif_member`** — look up the exact WIF principal already bound to
   `terraform-ci` (`gcloud iam service-accounts get-iam-policy terraform-ci@<project>.iam.gserviceaccount.com`)
   and reuse it: set it in `terraform.tfvars` locally, and as a new `GCP_WIF_MEMBER` repository
   variable for CI.

CI also needs two new repository variables: `GCP_REGION` (matching `var.region`'s value) and
`GCP_INGESTION_DEPLOY_SERVICE_ACCOUNT` (`ingestion-deploy@<project>.iam.gserviceaccount.com` —
predictable ahead of the first apply, since the account ID is fixed in `iam.tf`).

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
