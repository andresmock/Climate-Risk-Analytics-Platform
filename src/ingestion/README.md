# ingestion

Cloud Run service that pulls weather data from [Open-Meteo](https://open-meteo.com/) and lands
it, unmodified, in Google Cloud Storage. Triggered on a schedule by Cloud Scheduler.

This is currently a placeholder — see [docs/adr/0002](../../docs/adr/0002-initial-architecture-and-technology-stack.md)
for the architectural decision behind Cloud Run + Dockerfile, and `docs/vision.md` for the
milestone this service belongs to. The actual ingestion logic lands in the next milestone.
