from datetime import date

import pytest
import requests
import responses

from ingestion.locations import Location
from ingestion.open_meteo import (
    FORECAST_URL,
    HISTORICAL_URL,
    fetch_all,
    fetch_forecast,
    fetch_historical,
)

ZURICH = Location("Zurich", 47.3769, 8.5417)
MADRID = Location("Madrid", 40.4168, -3.7038)


@responses.activate
def test_fetch_forecast_returns_raw_json_unmodified():
    payload = {"latitude": 47.3769, "longitude": 8.5417, "hourly": {"temperature_2m": [1.0]}}
    responses.add(responses.GET, FORECAST_URL, json=payload, status=200)

    result = fetch_forecast(ZURICH)

    assert result == payload


@responses.activate
def test_fetch_forecast_requests_the_location_and_configured_variables():
    responses.add(responses.GET, FORECAST_URL, json={}, status=200)

    fetch_forecast(ZURICH)

    request_url = responses.calls[0].request.url
    assert "latitude=47.3769" in request_url
    assert "longitude=8.5417" in request_url
    assert "temperature_2m" in request_url
    assert "precipitation" in request_url
    assert "wind_speed_10m" in request_url


@responses.activate
def test_fetch_forecast_raises_on_http_error():
    responses.add(responses.GET, FORECAST_URL, status=500)

    with pytest.raises(requests.HTTPError):
        fetch_forecast(ZURICH)


@responses.activate
def test_fetch_all_pairs_each_location_with_its_own_response():
    responses.add(responses.GET, FORECAST_URL, json={"city": "zurich"}, status=200)
    responses.add(responses.GET, FORECAST_URL, json={"city": "madrid"}, status=200)

    result = fetch_all([ZURICH, MADRID])

    assert result == [
        (ZURICH, {"city": "zurich"}),
        (MADRID, {"city": "madrid"}),
    ]


@responses.activate
def test_fetch_historical_returns_raw_json_unmodified():
    payload = {"latitude": 47.34622, "hourly": {"temperature_2m": [9.5]}}
    responses.add(responses.GET, HISTORICAL_URL, json=payload, status=200)

    result = fetch_historical(ZURICH, date(2026, 10, 1), date(2026, 10, 14))

    assert result == payload


@responses.activate
def test_fetch_historical_requests_the_location_date_range_and_configured_variables():
    responses.add(responses.GET, HISTORICAL_URL, json={}, status=200)

    fetch_historical(ZURICH, date(2026, 10, 1), date(2026, 10, 14))

    request_url = responses.calls[0].request.url
    assert "latitude=47.3769" in request_url
    assert "longitude=8.5417" in request_url
    assert "start_date=2026-10-01" in request_url
    assert "end_date=2026-10-14" in request_url
    assert "temperature_2m" in request_url
    assert "precipitation" in request_url
    assert "wind_speed_10m" in request_url


@responses.activate
def test_fetch_historical_raises_on_http_error():
    responses.add(responses.GET, HISTORICAL_URL, status=400)

    with pytest.raises(requests.HTTPError):
        fetch_historical(ZURICH, date(2026, 10, 1), date(2026, 10, 14))
