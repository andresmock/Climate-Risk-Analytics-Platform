import json
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

from ingestion.locations import Location
from ingestion.storage import upload_raw

MEXICO_CITY = Location("Mexico City", 19.4326, -99.1332)
RUN_TIMESTAMP = datetime(2026, 8, 13, 18, 30, 0, tzinfo=UTC)


@patch("ingestion.storage.storage.Client")
def test_upload_raw_builds_the_expected_blob_path(mock_client_cls):
    mock_client = mock_client_cls.return_value
    mock_blob = mock_client.bucket.return_value.blob.return_value

    path = upload_raw("raw-bucket", "forecast", MEXICO_CITY, RUN_TIMESTAMP, {"hourly": {}})

    assert path == "open-meteo/forecast/mexico-city/20260813T183000Z.json"
    mock_client.bucket.assert_called_once_with("raw-bucket")
    mock_client.bucket.return_value.blob.assert_called_once_with(path)
    assert mock_blob.upload_from_string.call_count == 1


@patch("ingestion.storage.storage.Client")
def test_upload_raw_appends_the_suffix_under_the_dataset_prefix(mock_client_cls):
    path = upload_raw(
        "raw-bucket",
        "historical",
        MEXICO_CITY,
        RUN_TIMESTAMP,
        {"hourly": {}},
        suffix="_20260801_20260814",
    )

    assert path == "open-meteo/historical/mexico-city/20260813T183000Z_20260801_20260814.json"


@patch("ingestion.storage.storage.Client")
def test_upload_raw_uploads_the_exact_unmodified_payload(mock_client_cls: MagicMock):
    mock_client = mock_client_cls.return_value
    mock_blob = mock_client.bucket.return_value.blob.return_value
    payload = {"hourly": {"temperature_2m": [1.0, 2.0]}}

    upload_raw("raw-bucket", "forecast", MEXICO_CITY, RUN_TIMESTAMP, payload)

    _, kwargs = mock_blob.upload_from_string.call_args
    assert json.loads(kwargs["data"]) == payload
    assert kwargs["content_type"] == "application/json"
