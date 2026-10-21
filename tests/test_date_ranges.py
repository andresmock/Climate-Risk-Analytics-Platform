from datetime import date
from itertools import pairwise

import pytest

from ingestion.date_ranges import MAX_DAYS_PER_REQUEST, date_range, split_range

TODAY = date(2026, 10, 19)
WINDOW_DAYS = 14
PREFIX = "HISTORICAL"


@pytest.fixture(autouse=True)
def no_backfill_env(monkeypatch):
    for prefix in ("HISTORICAL", "PREVIOUS_RUNS"):
        monkeypatch.delenv(f"{prefix}_START_DATE", raising=False)
        monkeypatch.delenv(f"{prefix}_END_DATE", raising=False)


def test_date_range_defaults_to_trailing_window_ending_yesterday():
    start_date, end_date = date_range(TODAY, WINDOW_DAYS, PREFIX)

    assert end_date == date(2026, 10, 18)
    assert (end_date - start_date).days + 1 == WINDOW_DAYS


def test_date_range_uses_backfill_env_vars_when_set(monkeypatch):
    monkeypatch.setenv("HISTORICAL_START_DATE", "2024-10-01")
    monkeypatch.setenv("HISTORICAL_END_DATE", "2026-09-30")

    assert date_range(TODAY, WINDOW_DAYS, PREFIX) == (date(2024, 10, 1), date(2026, 9, 30))


def test_date_range_ignores_another_prefix_backfill_env_vars(monkeypatch):
    monkeypatch.setenv("PREVIOUS_RUNS_START_DATE", "2024-10-01")
    monkeypatch.setenv("PREVIOUS_RUNS_END_DATE", "2026-09-30")

    assert date_range(TODAY, WINDOW_DAYS, PREFIX)[1] == date(2026, 10, 18)


def test_date_range_requires_both_backfill_env_vars(monkeypatch):
    monkeypatch.setenv("HISTORICAL_START_DATE", "2024-10-01")

    with pytest.raises(RuntimeError, match="must be set together"):
        date_range(TODAY, WINDOW_DAYS, PREFIX)


def test_date_range_rejects_start_after_end(monkeypatch):
    monkeypatch.setenv("HISTORICAL_START_DATE", "2026-10-01")
    monkeypatch.setenv("HISTORICAL_END_DATE", "2026-09-01")

    with pytest.raises(RuntimeError, match="must not be after"):
        date_range(TODAY, WINDOW_DAYS, PREFIX)


def test_split_range_keeps_the_default_window_as_one_request():
    start_date, end_date = date_range(TODAY, WINDOW_DAYS, PREFIX)

    assert split_range(start_date, end_date) == [(start_date, end_date)]


def test_split_range_covers_the_whole_range_without_gaps_or_overlap():
    start_date, end_date = date(2024, 10, 1), date(2026, 9, 30)

    chunks = split_range(start_date, end_date)

    assert chunks[0][0] == start_date
    assert chunks[-1][1] == end_date
    for (_, previous_end), (next_start, _) in pairwise(chunks):
        assert (next_start - previous_end).days == 1
    assert all((end - start).days + 1 <= MAX_DAYS_PER_REQUEST for start, end in chunks)


def test_split_range_handles_a_single_day():
    day = date(2026, 10, 18)

    assert split_range(day, day) == [(day, day)]
