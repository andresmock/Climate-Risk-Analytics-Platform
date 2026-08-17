# IAM grants can take up to ~60s to propagate. Without this, terraform-ci's actAs grant on
# ingestion_runtime (terraform/iam.tf) can finish creating just before the Job below, but not
# yet be effective, producing a flaky "Permission 'iam.serviceaccounts.actAs' denied" 403.
resource "time_sleep" "wait_for_ingestion_runtime_actas" {
  depends_on      = [google_service_account_iam_member.terraform_ci_acts_as_ingestion_runtime]
  create_duration = "30s"
}

# Cloud Run Job, not Service: main.py runs the ingestion loop once and exits, it doesn't
# serve HTTP traffic. See docs/adr/0005 for the reasoning.
resource "google_cloud_run_v2_job" "ingestion" {
  name     = "ingestion"
  location = var.region

  depends_on = [time_sleep.wait_for_ingestion_runtime_actas]

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
