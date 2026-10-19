from datetime import date
from typing import Any

import requests

from ingestion.locations import Location

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
HISTORICAL_URL = "https://archive-api.open-meteo.com/v1/archive"
HOURLY_VARIABLES = ["temperature_2m", "precipitation", "wind_speed_10m"]


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


def fetch_historical(location: Location, start_date: date, end_date: date) -> dict[str, Any]:
    """Fetch the raw Open-Meteo historical weather (ERA5 reanalysis) response for a single
    location and inclusive date range. Same variables as the forecast, so the two line up."""
    response = requests.get(
        HISTORICAL_URL,
        params={
            "latitude": location.latitude,
            "longitude": location.longitude,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "hourly": ",".join(HOURLY_VARIABLES),
        },
        # Longer than the forecast's: a backfill chunk covers up to a month of hourly data.
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def fetch_all(locations: list[Location]) -> list[tuple[Location, dict[str, Any]]]:
    """Fetch the raw forecast response for each location, unmodified."""
    return [(location, fetch_forecast(location)) for location in locations]
