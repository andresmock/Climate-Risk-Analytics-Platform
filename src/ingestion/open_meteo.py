from typing import Any

import requests

from ingestion.locations import Location

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
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


def fetch_all(locations: list[Location]) -> list[tuple[Location, dict[str, Any]]]:
    """Fetch the raw forecast response for each location, unmodified."""
    return [(location, fetch_forecast(location)) for location in locations]
