# Cadence is a starting guess, not a measured one — see docs/adr/0005. Revisit if cost or
# forecast staleness argue for a different interval; it's a one-line change.
resource "google_cloud_scheduler_job" "ingestion" {
  name        = "ingestion-schedule"
  description = "Triggers the ingestion Cloud Run Job."
  schedule    = "0 */6 * * *"
  time_zone   = "UTC"

  http_target {
    http_method = "POST"
    # Cloud Run Jobs are triggered via the Admin API's `:run` method, not a URL the job
    # itself exposes — Jobs don't serve HTTP traffic (see cloud_run.tf).
    uri = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.ingestion.name}:run"

    oauth_token {
      service_account_email = google_service_account.scheduler_invoker.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}
