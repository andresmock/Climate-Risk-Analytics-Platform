# syntax=docker/dockerfile:1

FROM python:3.12-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.5.9 /uv /uvx /bin/

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

COPY pyproject.toml uv.lock* ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev || uv sync --no-install-project --no-dev

COPY src/ingestion ./src/ingestion

FROM python:3.12-slim

RUN groupadd --system app && useradd --system --gid app --no-create-home app

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src/ingestion /app/src/ingestion

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONPATH="/app/src" \
    PYTHONUNBUFFERED=1

USER app

# Placeholder entrypoint — replaced with the real ingestion service in the next milestone.
CMD ["python", "-c", "import ingestion; print(ingestion.__version__)"]
