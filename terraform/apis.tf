locals {
  required_apis = [
    "run.googleapis.com",              # Cloud Run
    "cloudscheduler.googleapis.com",   # Cloud Scheduler
    "bigquery.googleapis.com",         # BigQuery
    "storage.googleapis.com",          # Cloud Storage
    "artifactregistry.googleapis.com", # Cloud Run image registry
    "cloudbuild.googleapis.com",       # Cloud Build
    "iam.googleapis.com",              # IAM (service accounts, bindings)
    "iamcredentials.googleapis.com",   # Workload Identity Federation (GitHub Actions CI)
    "sts.googleapis.com",              # Workload Identity Federation (GitHub Actions CI)
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_apis)

  project = var.project_id
  service = each.value

  # Don't disable APIs on `terraform destroy` — they're a project-wide
  # dependency other things may rely on, not something to tear down with
  # whatever resource happened to require them first.
  disable_on_destroy = false
}
