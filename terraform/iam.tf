data "google_project" "current" {
  project_id = var.project_id
}

# Read-only identity for `terraform plan` in CI. Deliberately separate from terraform-ci:
# plan runs automatically on every same-repo PR with no human review, while apply is gated
# behind a required reviewer (see ci.yml). Sharing terraform-ci's write-capable identity would
# let an unreviewed PR reach terraform-ci's full blast radius via `terraform init`/`plan`
# executing provider code with live credentials — plan should only ever be able to read. See
# ADR-0007. Its project-level role (Viewer) and state-bucket access are granted by hand, same
# as terraform-ci's own role — this repo doesn't manage either.
resource "google_service_account" "terraform_plan" {
  account_id   = "terraform-plan"
  display_name = "Read-only identity for `terraform plan` in CI"
}

resource "google_service_account_iam_member" "terraform_plan_wif" {
  service_account_id = google_service_account.terraform_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = var.github_actions_wif_member
}

# Runtime identity for the ingestion Cloud Run Job itself. Write-only access to the raw
# bucket, nothing else — kept separate from terraform-ci, which manages infra shape, not
# ingestion's own runtime permissions.
resource "google_service_account" "ingestion_runtime" {
  account_id   = "ingestion-runtime"
  display_name = "Ingestion Cloud Run Job runtime identity"
}

resource "google_storage_bucket_iam_member" "ingestion_runtime_writes_raw" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.ingestion_runtime.email}"
}

# terraform-ci must be able to actAs ingestion_runtime to set it as the Cloud Run Job's
# runtime service account (see cloud_run.tf). Flagged as a future requirement in
# docs/adr/0004 when ingestion_runtime was introduced.
resource "google_service_account_iam_member" "terraform_ci_acts_as_ingestion_runtime" {
  service_account_id = google_service_account.ingestion_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:terraform-ci@${var.project_id}.iam.gserviceaccount.com"
}

# Deploy identity used by CI (via WIF, no stored key) to push new ingestion images and
# point the Cloud Run Job at them. See docs/adr/0005: deploys are deliberately decoupled
# from terraform-ci, which never touches the live image.
resource "google_service_account" "ingestion_deploy" {
  account_id   = "ingestion-deploy"
  display_name = "CI identity for ingestion image deploys"
}

resource "google_artifact_registry_repository_iam_member" "ingestion_deploy_pushes_images" {
  repository = google_artifact_registry_repository.ingestion.name
  location   = google_artifact_registry_repository.ingestion.location
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.ingestion_deploy.email}"
}

resource "google_cloud_run_v2_job_iam_member" "ingestion_deploy_updates_job" {
  name     = google_cloud_run_v2_job.ingestion.name
  location = google_cloud_run_v2_job.ingestion.location
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.ingestion_deploy.email}"
}

# Grants the same GitHub Actions workload identity pool that already impersonates
# terraform-ci permission to impersonate ingestion-deploy too. The pool itself is
# bootstrapped by hand, outside Terraform (see terraform/README.md) — same as
# terraform-ci's own binding, which this repo also doesn't manage.
resource "google_service_account_iam_member" "ingestion_deploy_wif" {
  service_account_id = google_service_account.ingestion_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = var.github_actions_wif_member
}

# `gcloud run jobs update` requires actAs on the job's *current* runtime service account for
# any update, even one that doesn't touch the service account field itself — the same
# requirement already granted to terraform-ci above, just missed for ingestion-deploy when
# ADR-0005 split deploys into their own identity.
resource "google_service_account_iam_member" "ingestion_deploy_acts_as_ingestion_runtime" {
  service_account_id = google_service_account.ingestion_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.ingestion_deploy.email}"
}

# Identity Cloud Scheduler uses to invoke the ingestion job. Separate from
# ingestion-deploy: this one only runs the job, it never updates it.
resource "google_service_account" "scheduler_invoker" {
  account_id   = "ingestion-scheduler"
  display_name = "Cloud Scheduler invoker for the ingestion job"
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_invokes_job" {
  name     = google_cloud_run_v2_job.ingestion.name
  location = google_cloud_run_v2_job.ingestion.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_invoker.email}"
}

# Cloud Scheduler mints OAuth tokens as its own Google-managed service agent, not as
# scheduler_invoker directly — it needs permission to mint tokens *as* that account.
resource "google_service_account_iam_member" "scheduler_agent_mints_invoker_tokens" {
  service_account_id = google_service_account.scheduler_invoker.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

# Default execution identity for the Dataform repository (terraform/dataform.tf): reads the
# raw external table, writes modelled output and assertion results. See docs/adr/0008.
resource "google_service_account" "dataform_runtime" {
  account_id   = "dataform-runtime"
  display_name = "Dataform repository runtime identity"
}

resource "google_bigquery_dataset_iam_member" "dataform_runtime_reads_raw" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataform_runtime.email}"
}

resource "google_bigquery_dataset_iam_member" "dataform_runtime_writes_warehouse" {
  dataset_id = google_bigquery_dataset.warehouse.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform_runtime.email}"
}

resource "google_bigquery_dataset_iam_member" "dataform_runtime_writes_warehouse_assertions" {
  dataset_id = google_bigquery_dataset.warehouse_assertions.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform_runtime.email}"
}

# Project-level, not dataset-scoped: BigQuery query-job creation has no dataset-scoped
# equivalent to jobUser (deliberate exception to docs/adr/0008's resource-scoped SA grants).
# Granted by hand, not via google_project_iam_member: terraform-ci holds no project-level
# setIamPolicy permission (docs/adr/0013).
# roles/bigquery.jobUser for serviceAccount:dataform-runtime@<project>.iam.gserviceaccount.com

# terraform-ci must be able to actAs dataform_runtime to set it as the Dataform repository's
# and workflow config's runtime service account (terraform/dataform.tf phase 2).
resource "google_service_account_iam_member" "terraform_ci_acts_as_dataform_runtime" {
  service_account_id = google_service_account.dataform_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:terraform-ci@${var.project_id}.iam.gserviceaccount.com"
}

# Dataform's Google-managed service agent (service-<project_number>@gcp-sa-dataform.iam.gserviceaccount.com)
# will need roles/iam.serviceAccountTokenCreator on dataform_runtime to mint OAuth tokens for
# scheduled workflow invocations — same shape as scheduler_agent_mints_invoker_tokens above.
# Deferred to the follow-up PR that creates the actual google_dataform_repository: the agent is
# only auto-provisioned by Google on first Dataform use, and granting a role to a
# not-yet-existent service account 400s (confirmed against a live project in run #80).
# **Verify at first scheduled run** whether this grant is actually required.

# Developer Connect's service agent needs this to create the Secret Manager secret backing
# this connection's GitHub App credentials (see docs/adr/0011). Granted by hand, not via
# google_project_iam_member: terraform-ci holds no project-level setIamPolicy permission
# (docs/adr/0013).
# roles/secretmanager.admin for serviceAccount:service-<project number>@gcp-sa-devconnect.iam.gserviceaccount.com

# Custom role for terraform-ci, replacing the broad predefined *.admin roles ADR-0006/0009/0010
# accumulated. Scoped to exactly what this repo's Terraform resources use, verified against
# gcloud list-testable-permissions (see docs/adr/0013). Excludes resourcemanager.projects.*
# IamPolicy — binding this role to terraform-ci itself is a manual, out-of-band step.
resource "google_project_iam_custom_role" "terraform_ci" {
  role_id     = "terraform_ci"
  title       = "terraform-ci (scoped)"
  description = "Least-privilege role for terraform-ci: exactly the permissions this repo's Terraform declares, no project-level IAM policy management. See docs/adr/0013."
  stage       = "GA"

  permissions = [
    # Service Usage (google_project_service)
    "serviceusage.services.enable",
    "serviceusage.services.disable",
    "serviceusage.services.get",
    "serviceusage.services.list",

    # Cloud Storage (google_storage_bucket, google_storage_bucket_iam_member)
    "storage.buckets.create",
    "storage.buckets.get",
    "storage.buckets.update",
    "storage.buckets.delete",
    "storage.buckets.getIamPolicy",
    "storage.buckets.setIamPolicy",

    # Artifact Registry (google_artifact_registry_repository, *_iam_member)
    "artifactregistry.repositories.create",
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.update",
    "artifactregistry.repositories.delete",
    "artifactregistry.repositories.getIamPolicy",
    "artifactregistry.repositories.setIamPolicy",

    # BigQuery (google_bigquery_dataset x3, google_bigquery_table, *_iam_member x3)
    "bigquery.datasets.create",
    "bigquery.datasets.get",
    "bigquery.datasets.update",
    "bigquery.datasets.delete",
    "bigquery.datasets.getIamPolicy",
    "bigquery.datasets.setIamPolicy",
    "bigquery.tables.create",
    "bigquery.tables.get",
    "bigquery.tables.update",
    "bigquery.tables.delete",

    # Cloud Run (google_cloud_run_v2_job, *_iam_member x2)
    "run.jobs.create",
    "run.jobs.get",
    "run.jobs.update",
    "run.jobs.delete",
    "run.jobs.getIamPolicy",
    "run.jobs.setIamPolicy",
    "run.operations.get", # LRO polling — Cloud Run job creation is long-running

    # Cloud Scheduler (google_cloud_scheduler_job)
    "cloudscheduler.jobs.create",
    "cloudscheduler.jobs.get",
    "cloudscheduler.jobs.fullView", # roles/cloudscheduler.admin carries this alongside .get
    "cloudscheduler.jobs.update",
    "cloudscheduler.jobs.delete",

    # Developer Connect (google_developer_connect_connection, google_developer_connect_git_repository_link)
    "developerconnect.connections.create",
    "developerconnect.connections.get",
    "developerconnect.connections.update",
    "developerconnect.connections.delete",
    "developerconnect.gitRepositoryLinks.create",
    "developerconnect.gitRepositoryLinks.get",
    "developerconnect.gitRepositoryLinks.delete",
    "developerconnect.gitRepositoryLinks.fetchReadWriteToken",
    "developerconnect.operations.get", # LRO polling — observed 20s+ connection creation in run #80
    "developerconnect.locations.get",

    # IAM (google_service_account x5, google_service_account_iam_member x6)
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.update",
    "iam.serviceAccounts.delete",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.setIamPolicy",

    # Dataform (google_dataform_repository, *_release_config, *_workflow_config —
    # terraform/dataform.tf). Not verified against gcloud list-testable-permissions (no live
    # resource existed yet to test against, unlike the rest of this list) — a missing permission
    # surfaces as PERMISSION_DENIED on apply, same fallback ADR-0013 already accepts elsewhere.
    "dataform.repositories.create",
    "dataform.repositories.get",
    "dataform.repositories.update",
    "dataform.repositories.delete",
    "dataform.releaseConfigs.create",
    "dataform.releaseConfigs.get",
    "dataform.releaseConfigs.update",
    "dataform.releaseConfigs.delete",
    "dataform.workflowConfigs.create",
    "dataform.workflowConfigs.get",
    "dataform.workflowConfigs.update",
    "dataform.workflowConfigs.delete",
  ]
}
