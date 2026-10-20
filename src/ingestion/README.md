# ingestion

Cloud Run Job that pulls weather data from [Open-Meteo](https://open-meteo.com/) and lands
it, unmodified, in Google Cloud Storage. Triggered on a schedule by Cloud Scheduler.

See [docs/adr/0002](../../docs/adr/0002-initial-architecture-and-technology-stack.md) for the
architectural decision behind Cloud Run + Dockerfile, and `docs/vision.md` for the milestone
this service belongs to.

## Status

Two datasets, both landed as unmodified API responses under their own GCS prefix (see
[ADR-0016](../../docs/adr/0016-historical-weather-ingestion.md)):

- `forecast`: the Forecast API response for each location in `locations.py`, written to
  `open-meteo/forecast/<location>/<run-timestamp>.json`.
- `historical`: the Historical Weather API (ERA5 reanalysis) response for the same locations
  and variables, written to `open-meteo/historical/<location>/<run-timestamp>_<start>_<end>.json`.
  By default it fetches the trailing 14 days up to yesterday (`historical.py`). Setting
  `HISTORICAL_START_DATE` and `HISTORICAL_END_DATE` (YYYY-MM-DD) replaces that window for a
  backfill, split into requests of at most 31 days each.

`open_meteo.py` fetches, `storage.py` uploads, and `main.py` is the Cloud Run entrypoint:
`python -m ingestion.main [forecast|historical]`, defaulting to `forecast` (the `Dockerfile`'s
`CMD`). It runs every request for the chosen dataset and exits non-zero if any of them fails.

Requires the `RAW_BUCKET_NAME` environment variable (the GCS bucket declared in
`terraform/storage.tf`) — the entrypoint fails fast if it's unset.

Both datasets run in GCP as separate Cloud Run Jobs from the same image, declared in
`terraform/` with their Cloud Scheduler triggers, Artifact Registry repository, and IAM (see
`terraform/README.md` and [ADR-0005](../../docs/adr/0005-ingestion-scheduling-and-deploys.md)):
`ingestion` runs `forecast` every 6 hours, and `ingestion-historical` runs `historical` daily at
05:00 UTC. The historical data was backfilled from October 2024 with a one-off run of
`ingestion-historical` using `HISTORICAL_START_DATE`/`HISTORICAL_END_DATE`.

Starter locations were picked to span distinct climate-risk profiles rather than arbitrary
coverage: Zurich (baseline), Mexico City (seismic), Madrid (extreme heat), Mumbai (monsoon
flooding) — though only the weather-driven signals are actually pulled today.
