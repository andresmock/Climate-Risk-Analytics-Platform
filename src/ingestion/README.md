# ingestion

Cloud Run service that pulls weather data from [Open-Meteo](https://open-meteo.com/) and lands
it, unmodified, in Google Cloud Storage. Triggered on a schedule by Cloud Scheduler.

See [docs/adr/0002](../../docs/adr/0002-initial-architecture-and-technology-stack.md) for the
architectural decision behind Cloud Run + Dockerfile, and `docs/vision.md` for the milestone
this service belongs to.

## Status

`open_meteo.py` fetches the raw Forecast API response for each location in `locations.py`
(`fetch_forecast` for one, `fetch_all` for all of them). It's storage-agnostic by design — no
GCS write yet, and no Cloud Run entrypoint — those land once a GCP project exists to point at
(see [AGENT.md](../../AGENT.md) guardrails). The Dockerfile's `CMD` is still the scaffolding
placeholder.

Starter locations were picked to span distinct climate-risk profiles rather than arbitrary
coverage: Zurich (baseline), Mexico City (seismic), Madrid (extreme heat), Mumbai (monsoon
flooding) — though only the weather-driven signals are actually pulled today.
