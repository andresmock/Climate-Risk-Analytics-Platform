# Cadence is a starting guess, not a measured one — see docs/adr/0005. Revisit if cost or
# forecast staleness argue for a different interval; it's a one-line change.
resource "google_cloud_scheduler_job" "ingestion" {
  name        = "ingestion-schedule"
  description = "Triggers the ingestion Cloud Run Job."
  schedule    = "0 */6 * * *"
  time_zone   = "UTC"

  # Cloud Run Jobs are triggered via the Admin API's `:run` method, not a URL the job
  # itself exposes — Jobs don't serve HTTP traffic (see cloud_run.tf).
  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.ingestion.name}:run"

    oauth_token {
      service_account_email = google_service_account.ingestion_invoker.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}

# IAM grants can take up to ~60s to propagate — same flaky-403 guard as cloud_run.tf's
# wait_for_ingestion_runtime_actas, for terraform-apply's actAs on ingestion-invoker.
resource "time_sleep" "wait_for_ingestion_invoker_actas" {
  depends_on      = [google_service_account_iam_member.terraform_apply_acts_as_ingestion_invoker]
  create_duration = "30s"
}

# Daily is enough: ERA5 publishes about once a day, and each run re-fetches a 14-day window
# (docs/adr/0016). 05:00 UTC keeps clear of the forecast job's 6-hourly ticks and finishes well
# before the 06:30 Dataform run (dataform.tf).
resource "google_cloud_scheduler_job" "ingestion_historical" {
  name        = "ingestion-historical-schedule"
  description = "Triggers the ingestion-historical Cloud Run Job."
  schedule    = "0 5 * * *"
  time_zone   = "UTC"

  depends_on = [time_sleep.wait_for_ingestion_invoker_actas]

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.ingestion_historical.name}:run"

    oauth_token {
      service_account_email = google_service_account.ingestion_invoker.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}
