# 17. Previous-run forecasts ingestion

## Status

Accepted

## Context

The next planned step is a model that corrects Open-Meteo's temperature forecasts: given a fresh
forecast, predict how far off it will be and adjust it. `climate_risk_warehouse.forecast_errors_hourly`
already pairs forecasts with historical weather, but only for forecasts this platform fetched
itself, which go back a few weeks. Historical weather goes back to October 2024
([ADR-0016](0016-historical-weather-ingestion.md)). A model trained on a few weeks of forecasts
can't see a full year of seasons, and ADR-0016 left open where older forecasts would come from.

Open-Meteo offers three archives of past forecasts:

- The **Historical Forecast API** (from about 2022) stitches the first hours of each model run into
  one continuous series. It has no lead time: every value is a very short-range forecast, so it
  can't show how error grows with lead time.
- The **Single Runs API** returns the full horizon of one specific model run, queried by
  initialisation time. It goes back to March 2024 for ECMWF IFS but only to September 2025 for
  other models, and rebuilding a lead-time history would take one request per run.
- The **Previous Runs API** returns, for each hour, the value predicted N×24 hours earlier, as
  separate variables (`temperature_2m_previous_day1` to `_previous_day7`). Most models are archived
  from January 2024, it accepts `start_date` and `end_date`, and it serves the same models as the
  Forecast API.

## Decision

**Source: the Previous Runs API** (`previous-runs-api.open-meteo.com/v1/forecast`). It is the
only archive with lead time that covers the whole historical weather backfill in a handful of
requests. Like the forecast pull, requests name no model, so both use Open-Meteo's default
"best match" model for each location.

**Variables: all three forecast variables at lead days 1 to 7.** That is
`temperature_2m`, `precipitation` and `wind_speed_10m`, each with `_previous_day1` to
`_previous_day7`: 21 series per request. The first model only corrects temperature, but
precipitation and wind cost nothing extra to collect and keep the dataset aligned with the other
two. `_previous_day0` is left out: it is the latest run, the same thing the Forecast API returns.

**Naming: `previous-runs` in paths and job names, `previous_run_forecasts` in BigQuery.** The
raw prefix and job follow the API's name, as `historical` does. The tables say what the rows are,
forecasts from earlier runs, following [ADR-0015](0015-naming-consistency-cleanup.md).

- Raw files: `open-meteo/previous-runs/<location-slug>/<run-timestamp>_<start>_<end>.json`
- External table: `climate_risk_raw.previous_run_forecasts`, scoped to
  `open-meteo/previous-runs/*.json`. The response has the same top-level shape as the other two
  APIs (parallel `hourly` arrays), so it reuses their raw schema.
- Mart: `climate_risk_warehouse.previous_run_forecasts_hourly`, one row per location, hour and
  lead day (1 to 7). Staging unpivots the 21 series into long form, so lead day is a column, not
  part of a column name.

**Ingestion: a third Cloud Run Job from the same image, daily, with a backfill.** It follows
ADR-0016's pattern exactly: an `ingestion-previous-runs` job running the same container with a
different command, as the existing `ingestion-runtime` service account, on its own daily Cloud
Scheduler trigger, with the CI deploy updating its image. Each run requests a short trailing window
ending yesterday, and the one-off backfill from 2024-10-01 uses the same code path with explicit
dates, split into month-sized requests. The date-range and chunking logic from the historical
dataset is shared, not copied.

The daily run continues after the backfill instead of letting the platform's own forecasts take
over. Training data then keeps one consistent definition of lead time from October 2024 onwards.

**Duplicates resolve the same way as historical weather.** A past hour's earlier forecasts don't
change once those runs have happened, so overlapping windows produce identical duplicates.
Staging keeps the value from the most recently fetched file for each location, hour and lead day.

## Consequences

- A forecast-correction model can train on two years of forecasts at seven lead times, alongside
  the matching historical weather, from day one.
- **Lead time is defined differently in the two forecast datasets.** Here, lead day N means "the
  value from the latest run available N×24 hours before the hour". In `forecasts_hourly`, lead
  time is the number of hours between this platform's fetch and the forecast hour. A model trained
  on previous-run forecasts and applied to fetched forecasts sees slightly different inputs.
  The two datasets overlap from the first forecast ingestion onwards, so the size of that
  difference can be measured. How the model handles it, including whether serving should read
  previous-run forecasts too, is left to the ML ADR.
- "Best match" can switch the underlying model for a location over time, here and in the forecast
  pull alike. Errors can then shift without anything in this platform changing. Pinning a model
  would trade that away for a model whose archive may be shorter.
- Request size: 21 variables over a month-long chunk counts as several API calls under Open-Meteo's
  free-tier weighting. The full backfill (about 25 months × 4 locations) still totals a few hundred
  weighted calls, far below the daily limit.
- One more Cloud Run Job and Scheduler job to operate, and a third copy of the raw-schema external
  table pattern. The service account count doesn't change.
