resource "google_artifact_registry_repository" "ingestion" {
  repository_id = "ingestion"
  location      = var.region
  format        = "DOCKER"
  description   = "Container images for the ingestion Cloud Run Job."
}
