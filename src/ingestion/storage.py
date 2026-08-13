import json
from datetime import datetime
from typing import Any

from google.cloud import storage

from ingestion.locations import Location


def _blob_path(location: Location, run_timestamp: datetime) -> str:
    slug = location.name.lower().replace(" ", "-")
    return f"open-meteo/{slug}/{run_timestamp:%Y%m%dT%H%M%SZ}.json"


def upload_forecast(
    bucket_name: str,
    location: Location,
    run_timestamp: datetime,
    payload: dict[str, Any],
) -> str:
    """Upload a location's raw forecast response to GCS, unmodified. Returns the blob path."""
    path = _blob_path(location, run_timestamp)

    client = storage.Client()
    blob = client.bucket(bucket_name).blob(path)
    blob.upload_from_string(
        data=json.dumps(payload),
        content_type="application/json",
    )

    return path
