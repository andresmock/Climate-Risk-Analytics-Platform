resource "google_storage_bucket" "raw" {
  name     = "${var.project_id}-raw"
  location = var.region

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = false
}

# BigQuery dataset-level IAM (iam.tf's dataform_runtime_reads_raw) covers querying the external
# table's metadata, but forecasts_raw reads live GCS objects — that needs bucket-level access
# too, or every query globbing gs://<raw-bucket>/open-meteo/*.json fails with permission denied.
resource "google_storage_bucket_iam_member" "dataform_runtime_reads_raw_bucket" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.dataform_runtime.email}"
}
