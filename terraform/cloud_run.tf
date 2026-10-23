# IAM grants can take up to ~60s to propagate. Without this, terraform-apply's actAs grant on
# ingestion_runtime (terraform/iam.tf) can finish creating just before the Job below, but not
# yet be effective, producing a flaky "Permission 'iam.serviceaccounts.actAs' denied" 403.
resource "time_sleep" "wait_for_ingestion_runtime_actas" {
  depends_on      = [google_service_account_iam_member.terraform_apply_acts_as_ingestion_runtime]
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
      # No retries: a retry re-runs every location under a new run timestamp, duplicating the
      # ones that already succeeded. The next scheduled run (or, for the date-range jobs below,
      # the overlapping window) covers whatever failed.
      max_retries = 0

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
    # `client`/`client_version`: `gcloud run jobs update` (the same deploy command that
    # overwrites `image` above) stamps its own CLI identity here too, causing the same
    # spurious plan diff if left tracked.
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

# Historical weather ingestion (docs/adr/0016): same image as `ingestion`, run with the
# `historical` dataset argument on its own daily schedule, so a failure in one doesn't mark the
# other's run failed. The Dockerfile only sets CMD, so `command` must be given alongside `args` —
# `args` alone would replace CMD and try to execute `historical` as a program.
resource "google_cloud_run_v2_job" "ingestion_historical" {
  name     = "ingestion-historical"
  location = var.region

  depends_on = [time_sleep.wait_for_ingestion_runtime_actas]

  template {
    template {
      service_account = google_service_account.ingestion_runtime.email
      # Longer than `ingestion`'s: a multi-year backfill is ~100 sequential archive API requests.
      timeout     = "900s"
      max_retries = 0

      containers {
        # Placeholder, same as `ingestion` above — CI deploys the real image (ADR-0005).
        image   = "us-docker.pkg.dev/cloudrun/container/job:latest"
        command = ["python", "-m", "ingestion.main"]
        args    = ["historical"]

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
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

# Previous-run forecasts ingestion (docs/adr/0017): same pattern as `ingestion_historical`, with
# the `previous-runs` dataset argument. Same timeout, since its backfill is the same ~100
# month-sized requests.
resource "google_cloud_run_v2_job" "ingestion_previous_runs" {
  name     = "ingestion-previous-runs"
  location = var.region

  depends_on = [time_sleep.wait_for_ingestion_runtime_actas]

  template {
    template {
      service_account = google_service_account.ingestion_runtime.email
      timeout         = "900s"
      max_retries     = 0

      containers {
        # Placeholder, same as `ingestion` above — CI deploys the real image (ADR-0005).
        image   = "us-docker.pkg.dev/cloudrun/container/job:latest"
        command = ["python", "-m", "ingestion.main"]
        args    = ["previous-runs"]

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
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}
