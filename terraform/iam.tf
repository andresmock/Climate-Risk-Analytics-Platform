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
  role                = "roles/iam.workloadIdentityUser"
  member              = var.github_actions_wif_member
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
