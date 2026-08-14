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
  description = "Raw Open-Meteo forecast responses, one row per file in gs://<raw-bucket>/open-meteo/*.json."

  external_data_configuration {
    source_format = "NEWLINE_DELIMITED_JSON"
    # BigQuery allows only one wildcard per source URI. A single `*` still matches across the
    # `/` in `open-meteo/<location>/<timestamp>.json`, since GCS object names are flat strings,
    # not real directories.
    source_uris = ["gs://${google_storage_bucket.raw.name}/open-meteo/*.json"]

    # Explicit schema, not autodetect: autodetect requires a matching file to already exist in
    # GCS at apply time, which makes table creation depend on the ingestion service having run.
    # `hourly`/`hourly_units` stay as opaque JSON rather than flattened RECORD/REPEATED fields —
    # unnesting the time series is Dataform's job, not the raw layer's.
    autodetect = false
    schema = jsonencode([
      { name = "latitude", type = "FLOAT64" },
      { name = "longitude", type = "FLOAT64" },
      { name = "generationtime_ms", type = "FLOAT64" },
      { name = "utc_offset_seconds", type = "INT64" },
      { name = "timezone", type = "STRING" },
      { name = "timezone_abbreviation", type = "STRING" },
      { name = "elevation", type = "FLOAT64" },
      { name = "hourly_units", type = "JSON" },
      { name = "hourly", type = "JSON" },
    ])

    # If Open-Meteo's response shape changes, unrecognized fields are silently skipped rather
    # than erroring queries — GCS still keeps every byte, so widening the schema later recovers
    # full visibility into both historical and new files without needing to re-ingest anything.
    ignore_unknown_values = true
  }
}
