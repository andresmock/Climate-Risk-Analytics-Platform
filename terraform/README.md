# terraform

Infrastructure as code for the platform's GCP resources (see
[docs/adr/0002](../docs/adr/0002-initial-architecture-and-technology-stack.md)).

This is currently a skeleton: provider/version constraints and variables only, using a local
backend, so `terraform init`/`validate` work without any live GCP project or credentials.

No actual resources (GCS buckets, BigQuery datasets, Cloud Run service, Cloud Scheduler jobs,
IAM) are declared yet — those land with the ingestion milestone, along with migrating the
backend to remote GCS state once a real project exists.
