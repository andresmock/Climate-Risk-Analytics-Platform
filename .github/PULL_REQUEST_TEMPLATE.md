## What


## Why


## How


## Checklist

- [ ] `ruff check .` passes
- [ ] `ruff format --check .` passes
- [ ] `pytest` passes
- [ ] `terraform fmt -check -recursive` and `terraform validate` pass (if `terraform/` changed)
- [ ] `dataform compile` passes (if `definitions/` or `workflow_settings.yaml` changed)
- [ ] `docker build -f src/ingestion/Dockerfile .` succeeds (if `src/ingestion/` or its `Dockerfile` changed)
- [ ] Relevant ADR added/updated under `docs/adr/` (if this changes architecture, tooling, or process)
