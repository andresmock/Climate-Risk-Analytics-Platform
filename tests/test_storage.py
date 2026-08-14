import json
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

from ingestion.locations import Location
from ingestion.storage import upload_forecast

MEXICO_CITY = Location("Mexico City", 19.4326, -99.1332)
RUN_TIMESTAMP = datetime(2026, 8, 13, 18, 30, 0, tzinfo=UTC)


@patch("ingestion.storage.storage.Client")
def test_upload_forecast_builds_the_expected_blob_path(mock_client_cls):
    mock_client = mock_client_cls.return_value
    mock_blob = mock_client.bucket.return_value.blob.return_value

    path = upload_forecast("raw-bucket", MEXICO_CITY, RUN_TIMESTAMP, {"hourly": {}})

    assert path == "open-meteo/mexico-city/20260813T183000Z.json"
    mock_client.bucket.assert_called_once_with("raw-bucket")
    mock_client.bucket.return_value.blob.assert_called_once_with(path)
    assert mock_blob.upload_from_string.call_count == 1


@patch("ingestion.storage.storage.Client")
def test_upload_forecast_uploads_the_exact_unmodified_payload(mock_client_cls: MagicMock):
    mock_client = mock_client_cls.return_value
    mock_blob = mock_client.bucket.return_value.blob.return_value
    payload = {"hourly": {"temperature_2m": [1.0, 2.0]}}

    upload_forecast("raw-bucket", MEXICO_CITY, RUN_TIMESTAMP, payload)

    _, kwargs = mock_blob.upload_from_string.call_args
    assert json.loads(kwargs["data"]) == payload
    assert kwargs["content_type"] == "application/json"
