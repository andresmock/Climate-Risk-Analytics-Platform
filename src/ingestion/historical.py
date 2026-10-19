import os
from datetime import date, timedelta

# Each daily run re-fetches this many days, so every day is fetched again after ERA5's ~5-day
# publication delay has passed (see docs/adr/0016).
WINDOW_DAYS = 14

# Upper bound per API request, so a multi-year backfill becomes a series of month-sized
# responses instead of one huge one. Also keeps the default window to a single request.
MAX_DAYS_PER_REQUEST = 31


def date_range(today: date) -> tuple[date, date]:
    """The inclusive date range to fetch: the trailing window ending yesterday, unless
    HISTORICAL_START_DATE and HISTORICAL_END_DATE (YYYY-MM-DD) override it for a backfill."""
    start = os.environ.get("HISTORICAL_START_DATE")
    end = os.environ.get("HISTORICAL_END_DATE")

    if start or end:
        if not (start and end):
            raise RuntimeError("HISTORICAL_START_DATE and HISTORICAL_END_DATE must be set together")
        start_date, end_date = date.fromisoformat(start), date.fromisoformat(end)
        if start_date > end_date:
            raise RuntimeError("HISTORICAL_START_DATE must not be after HISTORICAL_END_DATE")
        return start_date, end_date

    end_date = today - timedelta(days=1)
    return end_date - timedelta(days=WINDOW_DAYS - 1), end_date


def split_range(start_date: date, end_date: date) -> list[tuple[date, date]]:
    """Split an inclusive date range into consecutive chunks of at most MAX_DAYS_PER_REQUEST."""
    chunks = []
    chunk_start = start_date
    while chunk_start <= end_date:
        chunk_end = min(chunk_start + timedelta(days=MAX_DAYS_PER_REQUEST - 1), end_date)
        chunks.append((chunk_start, chunk_end))
        chunk_start = chunk_end + timedelta(days=1)
    return chunks
