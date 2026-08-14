resource "google_bigquery_dataset" "warehouse" {
  dataset_id  = "climate_risk"
  location    = var.region
  description = "Modelled climate/weather data, materialized by Dataform."
}

resource "google_bigquery_dataset" "warehouse_assertions" {
  dataset_id  = "climate_risk_assertions"
  location    = var.region
  description = "Dataform assertion results for the climate_risk dataset."
}

resource "google_bigquery_dataset" "raw" {
  dataset_id  = "climate_risk_raw"
  location    = var.region
  description = "Raw ingestion output, queried directly from GCS. Source for Dataform, not modelled."
}

# External table over the raw GCS objects: BigQuery reads them where they sit, so there's a
# single copy of the data (GCS) rather than a second write path that could drift out of sync.
resource "google_bigquery_table" "forecasts_raw" {
  dataset_id  = google_bigquery_dataset.raw.dataset_id
  table_id    = "forecasts"
  description = "Raw Open-Meteo forecast responses, one row per file in gs://<raw-bucket>/open-meteo/*/*.json."

  external_data_configuration {
    source_format = "NEWLINE_DELIMITED_JSON"
    source_uris   = ["gs://${google_storage_bucket.raw.name}/open-meteo/*/*.json"]
    autodetect    = true
  }
}
