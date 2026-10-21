# Climate Risk Analytics Platform

An open-source reference implementation of a modern, cloud-native data engineering and
analytics platform, built on Google Cloud Platform (GCP) around public weather and climate
data.

This is not a production system — it's a reference implementation demonstrating how a
scalable, well-documented, maintainable analytics platform can be designed and built
incrementally, using industry-standard tooling and public data sources.

See [docs/vision.md](docs/vision.md) for the full motivation and long-term direction, and
[docs/adr/](docs/adr/) for the architecture decisions behind everything below.

## Status

Two Open-Meteo datasets flow end to end, from scheduled ingestion through GCS and BigQuery into
Dataform-modelled tables:

- **Forecasts:** pulled every 6 hours for four locations. `climate_risk_warehouse.forecasts_hourly`
  keeps every forecast revision, so changes between runs stay visible.
- **Historical weather:** ERA5 reanalysis for the same locations and variables, pulled daily and
  backfilled to October 2024. `climate_risk_warehouse.historical_weather_hourly` holds one value
  per location and hour, the ground truth forecasts are measured against
  ([ADR-0016](docs/adr/0016-historical-weather-ingestion.md)).
- **Forecast error:** `climate_risk_warehouse.forecast_errors_hourly` joins the two, giving each
  forecast's error against historical weather by lead time.

Raw data stays in GCS and is queried through BigQuery external tables (`climate_risk_raw`).
Dataform recompiles `main` daily and runs 30 minutes after each forecast ingestion, with
assertions on every mart.

## Architecture

```
Open-Meteo APIs (Forecast, Historical Weather)
      │
      ▼
Cloud Run Jobs (scheduled by Cloud Scheduler)   — src/ingestion/
  ingestion: forecasts, every 6 hours
  ingestion-historical: historical weather, daily
      │
      ▼
Cloud Storage (raw)   open-meteo/forecast/, open-meteo/historical/
      │
      ▼
BigQuery (climate_risk_raw: external tables over GCS)
      │
      ▼
Dataform (staging views, marts + assertions)    — definitions/
      │
      ▼
BigQuery (climate_risk_warehouse)
```

All infrastructure is declared in Terraform (`terraform/`). See
[ADR-0002](docs/adr/0002-initial-architecture-and-technology-stack.md) for the reasoning
behind each choice.

## Tech stack

| Layer               | Choice                          |
|---------------------|----------------------------------|
| Compute             | Cloud Run (own Dockerfile)       |
| Scheduling          | Cloud Scheduler                  |
| Raw storage         | Cloud Storage                    |
| Warehouse           | BigQuery                         |
| Transformation      | Dataform                         |
| Infrastructure      | Terraform                        |
| Language / tooling  | Python, `uv`, `ruff`, `pytest`    |
| CI                  | GitHub Actions                   |

## Repository layout

- `src/ingestion/` — Cloud Run ingestion service and its `Dockerfile`
- `terraform/` — infrastructure as code
- `definitions/` — Dataform SQLX models (BigQuery transformations); `workflow_settings.yaml` at
  the repo root configures the Dataform project (see `definitions/README.md`)
- `docs/adr/` — architecture decision records
- `docs/vision.md` — project motivation and long-term direction
- `tests/` — Python test suite

## License

See [LICENSE](LICENSE).
