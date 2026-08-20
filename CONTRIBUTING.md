# Contributing

## Setup

- Python: `uv sync --all-groups`
- Terraform: standard CLI, but see "Running `terraform apply` locally" below before touching the real project.

## Before opening a PR

- `uv run ruff check .`
- `uv run ruff format --check .`
- `uv run pytest`
- If `terraform/` changed: `terraform fmt -check -recursive` and `terraform validate` (CI's `terraform-check`/`terraform-plan` jobs also run these; `terraform-plan` posts the plan as a PR comment on same-repo PRs)
- If `dataform/` changed: `npx --yes @dataform/cli@3.0.0 compile` from `dataform/`
- If `src/ingestion/` or its `Dockerfile` changed: `docker build -f src/ingestion/Dockerfile .`
- Add or update an ADR under `docs/adr/` if the change affects architecture, tooling, or process — see [ADR-0001](docs/adr/0001-record-architecture-decisions.md) for the supersede-don't-edit convention this repo follows.
- Fill out the PR template's checklist (`.github/PULL_REQUEST_TEMPLATE.md`).

## What CI does automatically vs. what you do locally

| Touching...                                          | CI does automatically                                                                          | You also need to |
|--------------------------------------------------------|--------------------------------------------------------------------------------------------------|-------------------|
| `terraform/**`                                          | `terraform-check` (fmt/validate) on every push/PR; `terraform-plan` posts a plan as a PR comment; a daily `terraform-drift` job fails if `main` has unapplied changes | After merging, run `terraform apply` yourself against the real project — CI never applies. See [ADR-0012](docs/adr/0012-terraform-apply-moves-local-only.md) and [ADR-0014](docs/adr/0014-terraform-drift-detection.md). |
| `src/ingestion/**`, `pyproject.toml`, `uv.lock`          | On push to `main`: builds the image, pushes it, and updates the live Cloud Run Job               | Nothing — fully automatic. See [ADR-0005](docs/adr/0005-ingestion-scheduling-and-deploys.md). |
| `dataform/**`                                            | Compiles the SQLX project (no live BigQuery connection)                                          | Nothing yet — deploying the compiled output isn't wired up yet. |
| Python (`src/`, `tests/`, `pyproject.toml`)              | `ruff check`, `ruff format --check`, `pytest` on every push/PR                                   | Nothing beyond passing CI. |

## Running `terraform apply` locally

Per [ADR-0012](docs/adr/0012-terraform-apply-moves-local-only.md), `terraform apply` against the real project only ever runs locally, authenticated by impersonating the `terraform-ci` service account — never in CI. If you need to do this and don't already have that access, ask a maintainer. See [`terraform/README.md`](terraform/README.md#applying-changes) for the exact setup and commands.

## Architecture decisions

Non-trivial architecture, tooling, or process changes should come with an ADR in `docs/adr/`. Decisions are recorded there and superseded — never edited in place — as things change; see [ADR-0001](docs/adr/0001-record-architecture-decisions.md).
