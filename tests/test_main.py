from datetime import date
from unittest.mock import patch

import pytest

from ingestion.historical import WINDOW_DAYS
from ingestion.locations import LOCATIONS
from ingestion.main import run


@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("RAW_BUCKET_NAME", "raw-bucket")
    monkeypatch.delenv("HISTORICAL_START_DATE", raising=False)
    monkeypatch.delenv("HISTORICAL_END_DATE", raising=False)


@patch("ingestion.main.upload_raw")
@patch("ingestion.main.fetch_forecast")
def test_run_ingests_every_location(mock_fetch, mock_upload):
    mock_fetch.return_value = {"hourly": {}}
    mock_upload.return_value = "open-meteo/forecast/zurich/20260813T183000Z.json"

    exit_code = run()

    assert exit_code == 0
    assert mock_fetch.call_count == len(LOCATIONS)
    assert mock_upload.call_count == len(LOCATIONS)
    assert all(call.args[1] == "forecast" for call in mock_upload.call_args_list)


@patch("ingestion.main.upload_raw")
@patch("ingestion.main.fetch_forecast")
def test_run_attempts_every_location_even_if_one_fails(mock_fetch, mock_upload):
    mock_fetch.side_effect = [Exception("boom"), *([{"hourly": {}}] * (len(LOCATIONS) - 1))]

    exit_code = run()

    assert exit_code == 1
    assert mock_fetch.call_count == len(LOCATIONS)
    assert mock_upload.call_count == len(LOCATIONS) - 1


@patch("ingestion.main.upload_raw")
@patch("ingestion.main.fetch_historical")
def test_run_historical_fetches_the_default_window_once_per_location(mock_fetch, mock_upload):
    mock_fetch.return_value = {"hourly": {}}

    exit_code = run("historical")

    assert exit_code == 0
    assert mock_fetch.call_count == len(LOCATIONS)
    _, start_date, end_date = mock_fetch.call_args.args
    assert (end_date - start_date).days + 1 == WINDOW_DAYS
    for call in mock_upload.call_args_list:
        assert call.args[1] == "historical"
        assert call.args[5] == f"_{start_date:%Y%m%d}_{end_date:%Y%m%d}"


@patch("ingestion.main.upload_raw")
@patch("ingestion.main.fetch_historical")
def test_run_historical_backfill_uploads_each_chunk_separately(
    mock_fetch, mock_upload, monkeypatch
):
    monkeypatch.setenv("HISTORICAL_START_DATE", "2026-07-01")
    monkeypatch.setenv("HISTORICAL_END_DATE", "2026-09-30")
    mock_fetch.return_value = {"hourly": {}}

    exit_code = run("historical")

    assert exit_code == 0
    chunks_per_location = mock_fetch.call_count // len(LOCATIONS)
    assert chunks_per_location > 1
    suffixes = [call.args[5] for call in mock_upload.call_args_list]
    assert len(set(suffixes)) == chunks_per_location
    assert min(call.args[1] for call in mock_fetch.call_args_list) == date(2026, 7, 1)
    assert max(call.args[2] for call in mock_fetch.call_args_list) == date(2026, 9, 30)


def test_run_rejects_unknown_dataset():
    with pytest.raises(ValueError, match="Unknown dataset"):
        run("observations")


def test_run_requires_raw_bucket_name(monkeypatch):
    monkeypatch.delenv("RAW_BUCKET_NAME", raising=False)

    with pytest.raises(RuntimeError, match="RAW_BUCKET_NAME"):
        run()
