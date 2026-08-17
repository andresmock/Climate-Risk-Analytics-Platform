# Cloud Run Job, not Service: main.py runs the ingestion loop once and exits, it doesn't
# serve HTTP traffic. See docs/adr/0005 for the reasoning.
resource "google_cloud_run_v2_job" "ingestion" {
  name     = "ingestion"
  location = var.region

  template {
    template {
      service_account = google_service_account.ingestion_runtime.email
      timeout         = "300s"
      max_retries     = 1

      containers {
        # Placeholder only — nothing has been pushed to the repository yet at first apply.
        # CI overwrites this on every deploy (see ADR-0005); Terraform stops tracking the
        # field below so those deploys don't get reverted by the next `terraform apply`.
        image = "us-docker.pkg.dev/cloudrun/container/job:latest"

        env {
          name  = "RAW_BUCKET_NAME"
          value = google_storage_bucket.raw.name
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image]
  }
}
