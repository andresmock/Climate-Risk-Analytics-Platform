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
