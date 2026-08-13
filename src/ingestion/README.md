# ingestion

Cloud Run service that pulls weather data from [Open-Meteo](https://open-meteo.com/) and lands
it, unmodified, in Google Cloud Storage. Triggered on a schedule by Cloud Scheduler.

See [docs/adr/0002](../../docs/adr/0002-initial-architecture-and-technology-stack.md) for the
architectural decision behind Cloud Run + Dockerfile, and `docs/vision.md` for the milestone
this service belongs to.

## Status

`open_meteo.py` fetches the raw Forecast API response for each location in `locations.py`
(`fetch_forecast` for one, `fetch_all` for all of them). `storage.py` uploads each response,
unmodified, to the raw GCS bucket. `main.py` is the Cloud Run entrypoint (`Dockerfile`'s `CMD`):
it runs both for every location in `locations.py` and exits non-zero if any location fails.

Requires the `RAW_BUCKET_NAME` environment variable (the GCS bucket declared in
`terraform/storage.tf`) — the entrypoint fails fast if it's unset.

Not deployed yet: this runs the fetch-and-write logic, but no Cloud Run Job, Cloud Scheduler,
or IAM exists to actually run it in GCP (next step).

Starter locations were picked to span distinct climate-risk profiles rather than arbitrary
coverage: Zurich (baseline), Mexico City (seismic), Madrid (extreme heat), Mumbai (monsoon
flooding) — though only the weather-driven signals are actually pulled today.
