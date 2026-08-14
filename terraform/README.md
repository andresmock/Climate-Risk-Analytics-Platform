# terraform

Infrastructure as code for the platform's GCP resources (see
[docs/adr/0002](../docs/adr/0002-initial-architecture-and-technology-stack.md)).

A real GCP project now backs this config, with state stored remotely in GCS, the required APIs
(`apis.tf`) declared, the raw landing bucket (`storage.tf`), and the warehouse datasets
(`bigquery.tf`). The Cloud Run service, Cloud Scheduler job, Artifact Registry repository, and
IAM are not declared yet — those land once the ingestion service has a real entrypoint to
deploy (see `src/ingestion/README.md`).

To `init`/`plan`/`apply` against the real project, two gitignored files are required locally
(neither is committed — see `.gitignore`):

- `terraform.tfvars` — sets `project_id` to the real GCP project ID
- `backend.hcl` — sets the `bucket`/`prefix` for the remote state backend, passed via
  `terraform init -backend-config=backend.hcl`

Without them, `terraform validate` still works (no live project/credentials needed), but
`init`/`plan`/`apply` will fail or fall back to asking for the backend config interactively.
