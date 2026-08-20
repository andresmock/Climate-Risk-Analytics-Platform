# Project number, needed below for Google-managed service agent email addresses.
data "google_project" "current" {
  project_id = var.project_id
}

# ---- terraform-plan: read-only CI identity ----
# Separate from terraform-apply so an unreviewed PR can't reach terraform-apply's write-capable
# blast radius via `terraform init`/`plan` (ADR-0007). Role + state-bucket access granted by
# hand, not by this file.
resource "google_service_account" "terraform_plan" {
  account_id   = "terraform-plan"
  display_name = "Read-only identity for `terraform plan` in CI"
}

resource "google_service_account_iam_member" "terraform_plan_wif" {
  service_account_id = google_service_account.terraform_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = var.github_actions_wif_member
}

# ---- ingestion-runtime: the ingestion Cloud Run Job's own identity ----
# Write-only to the raw bucket, nothing else.
resource "google_service_account" "ingestion_runtime" {
  account_id   = "ingestion-runtime"
  display_name = "Ingestion Cloud Run Job runtime identity"
}

resource "google_storage_bucket_iam_member" "ingestion_runtime_writes_raw" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.ingestion_runtime.email}"
}

# terraform-apply needs actAs to assign this SA as the Cloud Run Job's runtime identity
# (cloud_run.tf).
resource "google_service_account_iam_member" "terraform_apply_acts_as_ingestion_runtime" {
  service_account_id = google_service_account.ingestion_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:terraform-apply@${var.project_id}.iam.gserviceaccount.com"
}

# ---- ingestion-deploy: CI identity for image pushes and job updates ----
# Decoupled from terraform-apply, which never touches the live image (ADR-0005).
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

# Lets GitHub Actions' WIF pool impersonate this SA too (pool itself bootstrapped by hand).
resource "google_service_account_iam_member" "ingestion_deploy_wif" {
  service_account_id = google_service_account.ingestion_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = var.github_actions_wif_member
}

# `run jobs update` requires actAs on the job's current runtime SA for any update, even one
# that doesn't touch it — missed when ADR-0005 split deploys out of terraform-apply.
resource "google_service_account_iam_member" "ingestion_deploy_acts_as_ingestion_runtime" {
  service_account_id = google_service_account.ingestion_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.ingestion_deploy.email}"
}

# ---- ingestion-invoker: Cloud Scheduler's invoker identity ----
# Runs the job only, never updates it — kept separate from ingestion-deploy.
resource "google_service_account" "ingestion_invoker" {
  account_id   = "ingestion-invoker"
  display_name = "Cloud Scheduler invoker for the ingestion job"
}

resource "google_cloud_run_v2_job_iam_member" "ingestion_invoker_invokes_job" {
  name     = google_cloud_run_v2_job.ingestion.name
  location = google_cloud_run_v2_job.ingestion.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.ingestion_invoker.email}"
}

# Cloud Scheduler's Google-managed agent mints OAuth tokens as ingestion_invoker.
resource "google_service_account_iam_member" "scheduler_agent_mints_invoker_tokens" {
  service_account_id = google_service_account.ingestion_invoker.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

# ---- dataform-runtime: the Dataform repository's execution identity ----
# Reads raw, writes modelled output and assertion results (dataform.tf, ADR-0008).
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

# terraform-apply needs actAs to assign this SA as Dataform's runtime identity (dataform.tf).
resource "google_service_account_iam_member" "terraform_apply_acts_as_dataform_runtime" {
  service_account_id = google_service_account.dataform_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:terraform-apply@${var.project_id}.iam.gserviceaccount.com"
}

# TODO: Dataform's service agent will need serviceAccountTokenCreator on dataform_runtime to
# mint tokens for scheduled runs (same shape as scheduler_agent_mints_invoker_tokens above).
# Deferred: the agent doesn't exist until first Dataform use, so granting it now 400s.
# Verify at first scheduled run whether this is actually required.

# ---- Manual grants: applied by hand, not managed by this file ----
# terraform-apply holds no project-level setIamPolicy permission (ADR-0013), so these can't be
# google_project_iam_member resources.
#
# roles/bigquery.jobUser for serviceAccount:dataform-runtime@<project>.iam.gserviceaccount.com
#   Project-level: query-job creation has no dataset-scoped equivalent to jobUser.
#
# roles/secretmanager.admin for serviceAccount:service-<project number>@gcp-sa-devconnect.iam.gserviceaccount.com
#   Lets Developer Connect's service agent create the secret backing its GitHub App
#   credentials (ADR-0011).
#
# roles/iam.roleAdmin for serviceAccount:terraform-apply@<project>.iam.gserviceaccount.com
#   The scoped custom role below deliberately grants no iam.roles.* or resourcemanager.projects.*
#   permissions (ADR-0013), so terraform-apply can't read or manage that role — or even read
#   basic project metadata (`data.google_project.current` above) — using only its own custom
#   role. roles/iam.roleAdmin covers both. Without this, every `plan`/`apply` fails on
#   google_project_iam_custom_role.terraform_apply and data.google_project.current with 403s
#   (see ADR-0015).

# ---- terraform-apply: custom role ----
# Exactly the permissions this repo's Terraform uses, replacing the broad *.admin roles
# ADR-0006/0009/0010 accumulated (ADR-0013). Binding this role — and roles/iam.roleAdmin above —
# to terraform-apply itself is a manual, out-of-band step.
resource "google_project_iam_custom_role" "terraform_apply" {
  role_id     = "terraform_apply"
  title       = "terraform-apply (scoped)"
  description = "Least-privilege role for terraform-apply: exactly the permissions this repo's Terraform declares, no project-level IAM policy management. See docs/adr/0013."
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

    # Dataform (google_dataform_repository, *_release_config, *_workflow_config — dataform.tf).
    # Unverified against list-testable-permissions (no live resource to test against yet).
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
