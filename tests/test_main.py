from unittest.mock import patch

import pytest

from ingestion.locations import LOCATIONS
from ingestion.main import run


@patch("ingestion.main.upload_forecast")
@patch("ingestion.main.fetch_forecast")
def test_run_ingests_every_location(mock_fetch, mock_upload, monkeypatch):
    monkeypatch.setenv("RAW_BUCKET_NAME", "raw-bucket")
    mock_fetch.return_value = {"hourly": {}}
    mock_upload.return_value = "open-meteo/zurich/20260813T183000Z.json"

    exit_code = run()

    assert exit_code == 0
    assert mock_fetch.call_count == len(LOCATIONS)
    assert mock_upload.call_count == len(LOCATIONS)


@patch("ingestion.main.upload_forecast")
@patch("ingestion.main.fetch_forecast")
def test_run_attempts_every_location_even_if_one_fails(mock_fetch, mock_upload, monkeypatch):
    monkeypatch.setenv("RAW_BUCKET_NAME", "raw-bucket")
    mock_fetch.side_effect = [Exception("boom"), *([{"hourly": {}}] * (len(LOCATIONS) - 1))]

    exit_code = run()

    assert exit_code == 1
    assert mock_fetch.call_count == len(LOCATIONS)
    assert mock_upload.call_count == len(LOCATIONS) - 1


def test_run_requires_raw_bucket_name(monkeypatch):
    monkeypatch.delenv("RAW_BUCKET_NAME", raising=False)

    with pytest.raises(RuntimeError, match="RAW_BUCKET_NAME"):
        run()
