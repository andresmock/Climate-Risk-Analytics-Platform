from datetime import date
from typing import Any

import requests

from ingestion.locations import Location

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
HISTORICAL_URL = "https://archive-api.open-meteo.com/v1/archive"
PREVIOUS_RUNS_URL = "https://previous-runs-api.open-meteo.com/v1/forecast"
HOURLY_VARIABLES = ["temperature_2m", "precipitation", "wind_speed_10m"]
# Day 0 is the latest run, the same thing the Forecast API returns (see docs/adr/0017).
PREVIOUS_RUN_LEAD_DAYS = range(1, 8)


def fetch_forecast(location: Location) -> dict[str, Any]:
    """Fetch the raw Open-Meteo forecast response for a single location."""
    response = requests.get(
        FORECAST_URL,
        params={
            "latitude": location.latitude,
            "longitude": location.longitude,
            "hourly": ",".join(HOURLY_VARIABLES),
        },
        timeout=10,
    )
    response.raise_for_status()
    return response.json()


def _fetch_range(
    url: str, location: Location, start_date: date, end_date: date, hourly: list[str]
) -> dict[str, Any]:
    response = requests.get(
        url,
        params={
            "latitude": location.latitude,
            "longitude": location.longitude,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "hourly": ",".join(hourly),
        },
        # Longer than the forecast's: a backfill chunk covers up to a month of hourly data.
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def fetch_historical(location: Location, start_date: date, end_date: date) -> dict[str, Any]:
    """Fetch the raw Open-Meteo historical weather (ERA5 reanalysis) response for a single
    location and inclusive date range. Same variables as the forecast, so the two line up."""
    return _fetch_range(HISTORICAL_URL, location, start_date, end_date, HOURLY_VARIABLES)


def fetch_previous_runs(location: Location, start_date: date, end_date: date) -> dict[str, Any]:
    """Fetch the raw Open-Meteo Previous Runs response for a single location and inclusive date
    range: each forecast variable as predicted 1 to 7 days before every hour in the range."""
    hourly = [
        f"{variable}_previous_day{lead_day}"
        for variable in HOURLY_VARIABLES
        for lead_day in PREVIOUS_RUN_LEAD_DAYS
    ]
    return _fetch_range(PREVIOUS_RUNS_URL, location, start_date, end_date, hourly)


def fetch_all(locations: list[Location]) -> list[tuple[Location, dict[str, Any]]]:
    """Fetch the raw forecast response for each location, unmodified."""
    return [(location, fetch_forecast(location)) for location in locations]
