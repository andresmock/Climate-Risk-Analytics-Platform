# 16. Historical weather ingestion and per-dataset raw layout

## Status

Accepted

## Context

Everything ingested so far is forecast data (`climate_risk_raw.forecasts`): what Open-Meteo
predicted would happen, never what actually did. That rules out the next planned step, a model
that learns to correct forecast error ([docs/vision.md](../vision.md)'s forecasting and risk
scoring direction), since there is no ground truth to measure error against. The platform needs a
second raw dataset recording past weather for the same locations and variables.

Adding one also exposes a problem with the existing raw layout. Forecast files live at
`open-meteo/<location-slug>/<run-timestamp>.json`, and the external table reads
`open-meteo/*.json`. That wildcard matches across `/` (GCS object names are flat strings, see
`terraform/bigquery.tf`), so any new file anywhere under `open-meteo/` would be silently picked
up by `climate_risk_raw.forecasts`.

## Decision

**Source: Open-Meteo's Historical Weather API** (`archive-api.open-meteo.com/v1/archive`),
requesting the same hourly variables as the forecast (`temperature_2m`, `precipitation`,
`wind_speed_10m`). Its response has the same shape as the Forecast API's (parallel `hourly`
arrays), so the raw table can reuse the forecast table's schema and staging can reuse
`stg_forecasts`' unnesting approach. Same provider, no new API keys, no new terms of use.

This is reanalysis data (ERA5 and related models), not weather station measurements: a model's
best reconstruction of past conditions on a grid of roughly 9 to 25 km, published with a delay of
about 5 days. That is good enough to measure forecast error against, and it covers decades, which
allows an immediate backfill instead of waiting months for history to accumulate. Station
observations from a second provider remain an option if reanalysis proves too coarse.

**Naming: `climate_risk_raw.historical_weather`**, not `observations`, following
[ADR-0015](0015-naming-consistency-cleanup.md)'s rule of naming things for what they are. Calling
reanalysis "observations" would overstate what the data is.

**Raw layout: one prefix per dataset under `open-meteo/`.**

- `open-meteo/forecast/<location-slug>/<run-timestamp>.json` (existing files move here)
- `open-meteo/historical/<location-slug>/<run-timestamp>.json`

Each external table's source URI is scoped to its own prefix (`open-meteo/forecast/*.json`,
`open-meteo/historical/*.json`), so neither can pick up the other's files. Moving the existing
forecast files was preferred over adding a new top-level prefix (e.g. `open-meteo-historical/`)
and leaving forecasts where they are: there are only a few weeks of forecast files today, and the
cost of moving them only grows over time.

**Ingestion: a separate Cloud Run Job from the same image.** A new `ingestion-historical` job
runs the same container as `ingestion` with a different command, on its own daily Cloud Scheduler
trigger. A failure in one doesn't mark the other's run failed, and each keeps its own cadence. The
CI deploy step ([ADR-0005](0005-ingestion-scheduling-and-deploys.md)) updates the image on both
jobs. Both run as the existing `ingestion-runtime` service account, since both need exactly the
same access: write to the raw bucket.

**Each file is one API response, stored unmodified, named by run timestamp**, the same as
forecasts. Each daily run requests a trailing window (the last 14 days), so every day is fetched
several times, including after ERA5's publication delay has passed. Overlapping windows and reruns
therefore produce duplicate rows across files by design. `stg_historical_weather` resolves them by
keeping, for each location and hour, the value from the most recent file that has one.

**Backfill uses the same code path**, with an explicit start and end date passed to the job as
environment variables in place of the trailing window, split into date ranges small enough to
finish within the job's timeout and stay under Open-Meteo's free-tier rate limits. It is run
manually, once.

**Migration order.** Moving the forecast files touches ingestion code, the forecasts external
table, and `stg_forecasts`' path regex, which ship by three different routes: CI deploy on merge,
local `terraform apply` ([ADR-0012](0012-terraform-apply-moves-local-only.md)), and Dataform's
daily recompile of `main` ([ADR-0008](0008-dataform-execution-model.md)). They land in one PR,
merged shortly after a Dataform run, followed straight away by `terraform apply` and a one-off
`gcloud storage mv` of the existing objects, so every route has caught up before the next
ingestion and Dataform runs.

## Consequences

- The platform has ground truth for the first time, which makes forecast-error modelling
  possible, with years of history available from day one through the backfill.
- Reanalysis is not station truth. Errors measured against it include reanalysis error, and grid
  resolution smooths local extremes (e.g. convective rain). Any model trained on it inherits this,
  and that needs stating wherever its results are presented.
- ERA5 publishes preliminary values first and revises them a few months later. The 14-day window
  captures the preliminary values only; picking up the later revisions would mean periodically
  re-running the backfill over older ranges. That isn't planned yet.
- Storage grows with duplication: every hour of history is stored in roughly 9 to 14 files.
  At four locations and three variables this is negligible, and keeping files unmodified is worth
  more than the bytes saved by trimming each window to only its new days.
- One more Cloud Run Job and Scheduler job to operate. The service account count doesn't change.
- The forecast migration has a short window in which a Dataform run or ingestion run could see the
  old and new layouts mixed. Timing the merge right after a Dataform run keeps that window clear of
  any scheduled run. If it's missed, the result is one run's assertions failing or one run's files
  missing from the table until the next run, with nothing lost in GCS.
- Training a forecast-correction model also needs past forecasts going back as far as the
  historical data, which the current forecast ingestion doesn't have. Where those come from is
  left to the ML ADR.
