import logging
import os
import sys
from datetime import UTC, datetime

from ingestion.locations import LOCATIONS
from ingestion.open_meteo import fetch_forecast
from ingestion.storage import upload_forecast

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)


def run() -> int:
    bucket_name = os.environ.get("RAW_BUCKET_NAME")
    if not bucket_name:
        raise RuntimeError("RAW_BUCKET_NAME environment variable is required")

    run_timestamp = datetime.now(UTC)
    failures = 0

    for location in LOCATIONS:
        try:
            payload = fetch_forecast(location)
            path = upload_forecast(bucket_name, location, run_timestamp, payload)
            logger.info("%s -> gs://%s/%s", location.name, bucket_name, path)
        except Exception:
            failures += 1
            logger.exception("Failed to ingest %s", location.name)

    logger.info("Ingested %d/%d locations", len(LOCATIONS) - failures, len(LOCATIONS))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(run())
