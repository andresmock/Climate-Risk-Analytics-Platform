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

✅ First milestone complete: Open-Meteo weather data flows from ingestion into BigQuery
(`climate_risk_raw.forecasts`, an external table reading the raw GCS bucket directly).
Ingestion currently runs manually; deploying it to Cloud Run on a schedule, and building
the Dataform models on top of the raw table, are the next steps.

## Architecture

```
Open-Meteo API
      │
      ▼
Cloud Run (scheduled by Cloud Scheduler)   — src/ingestion/
      │
      ▼
Cloud Storage (raw)
      │
      ▼
BigQuery (warehouse)
      │
      ▼
Dataform (modelling + assertions)          — dataform/
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
- `dataform/` — BigQuery transformations
- `docs/adr/` — architecture decision records
- `docs/vision.md` — project motivation and long-term direction
- `tests/` — Python test suite

## License

See [LICENSE](LICENSE).
