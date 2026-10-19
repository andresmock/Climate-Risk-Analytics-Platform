import json
from datetime import datetime
from typing import Any

from google.cloud import storage

from ingestion.locations import Location


def _blob_path(dataset: str, location: Location, run_timestamp: datetime, suffix: str) -> str:
    slug = location.name.lower().replace(" ", "-")
    return f"open-meteo/{dataset}/{slug}/{run_timestamp:%Y%m%dT%H%M%SZ}{suffix}.json"


def upload_raw(
    bucket_name: str,
    dataset: str,
    location: Location,
    run_timestamp: datetime,
    payload: dict[str, Any],
    suffix: str = "",
) -> str:
    """Upload a location's raw API response to GCS, unmodified, under the dataset's own prefix
    (see docs/adr/0016). `suffix` keeps several responses from one run apart, e.g. a backfill's
    date-range chunks for the same location. Returns the blob path."""
    path = _blob_path(dataset, location, run_timestamp, suffix)

    client = storage.Client()
    blob = client.bucket(bucket_name).blob(path)
    blob.upload_from_string(
        data=json.dumps(payload),
        content_type="application/json",
    )

    return path
