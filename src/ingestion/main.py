import argparse
import logging
import os
import sys
from collections.abc import Callable
from datetime import UTC, datetime
from functools import partial
from typing import Any

from ingestion import historical
from ingestion.locations import LOCATIONS, Location
from ingestion.open_meteo import fetch_forecast, fetch_historical
from ingestion.storage import upload_raw

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)

DATASETS = ("forecast", "historical")

# (location, zero-argument fetch, blob path suffix)
Request = tuple[Location, Callable[[], dict[str, Any]], str]


def _requests(dataset: str, run_timestamp: datetime) -> list[Request]:
    if dataset == "forecast":
        return [(location, partial(fetch_forecast, location), "") for location in LOCATIONS]

    if dataset == "historical":
        start_date, end_date = historical.date_range(run_timestamp.date())
        return [
            (
                location,
                partial(fetch_historical, location, chunk_start, chunk_end),
                f"_{chunk_start:%Y%m%d}_{chunk_end:%Y%m%d}",
            )
            for location in LOCATIONS
            for chunk_start, chunk_end in historical.split_range(start_date, end_date)
        ]

    raise ValueError(f"Unknown dataset {dataset!r}, expected one of {DATASETS}")


def run(dataset: str = "forecast") -> int:
    bucket_name = os.environ.get("RAW_BUCKET_NAME")
    if not bucket_name:
        raise RuntimeError("RAW_BUCKET_NAME environment variable is required")

    run_timestamp = datetime.now(UTC)
    to_ingest = _requests(dataset, run_timestamp)
    failures = 0

    for location, fetch, suffix in to_ingest:
        try:
            payload = fetch()
            path = upload_raw(bucket_name, dataset, location, run_timestamp, payload, suffix)
            logger.info("%s -> gs://%s/%s", location.name, bucket_name, path)
        except Exception:
            failures += 1
            logger.exception("Failed to ingest %s%s", location.name, suffix)

    logger.info("Ingested %d/%d %s requests", len(to_ingest) - failures, len(to_ingest), dataset)
    return 1 if failures else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ingest raw Open-Meteo data into GCS.")
    parser.add_argument("dataset", nargs="?", default="forecast", choices=DATASETS)
    sys.exit(run(parser.parse_args().dataset))
