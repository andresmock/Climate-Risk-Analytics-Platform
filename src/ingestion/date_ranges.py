import os
from datetime import date, timedelta

# Each daily historical run re-fetches this many days, so every day is fetched again after ERA5's
# ~5-day publication delay has passed (see docs/adr/0016).
HISTORICAL_WINDOW_DAYS = 14

# A past hour's earlier forecasts don't change once those runs have happened, so the daily
# previous-runs window only needs to cover a couple of missed runs (see docs/adr/0017).
PREVIOUS_RUNS_WINDOW_DAYS = 3

# Upper bound per API request, so a multi-year backfill becomes a series of month-sized
# responses instead of one huge one. Also keeps each default window to a single request.
MAX_DAYS_PER_REQUEST = 31


def date_range(today: date, window_days: int, env_prefix: str) -> tuple[date, date]:
    """The inclusive date range to fetch: the trailing `window_days` ending yesterday, unless
    <env_prefix>_START_DATE and <env_prefix>_END_DATE (YYYY-MM-DD) override it for a backfill."""
    start_var, end_var = f"{env_prefix}_START_DATE", f"{env_prefix}_END_DATE"
    start = os.environ.get(start_var)
    end = os.environ.get(end_var)

    if start or end:
        if not (start and end):
            raise RuntimeError(f"{start_var} and {end_var} must be set together")
        start_date, end_date = date.fromisoformat(start), date.fromisoformat(end)
        if start_date > end_date:
            raise RuntimeError(f"{start_var} must not be after {end_var}")
        return start_date, end_date

    end_date = today - timedelta(days=1)
    return end_date - timedelta(days=window_days - 1), end_date


def split_range(start_date: date, end_date: date) -> list[tuple[date, date]]:
    """Split an inclusive date range into consecutive chunks of at most MAX_DAYS_PER_REQUEST."""
    chunks = []
    chunk_start = start_date
    while chunk_start <= end_date:
        chunk_end = min(chunk_start + timedelta(days=MAX_DAYS_PER_REQUEST - 1), end_date)
        chunks.append((chunk_start, chunk_end))
        chunk_start = chunk_end + timedelta(days=1)
    return chunks
