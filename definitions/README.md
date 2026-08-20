# definitions

BigQuery transformations, using [Dataform](https://cloud.google.com/dataform) (see
[docs/adr/0002](../docs/adr/0002-initial-architecture-and-technology-stack.md)). Lives at the
repository root alongside `../workflow_settings.yaml`, not nested under its own `dataform/`
directory — Google Cloud's git-linked Dataform repositories require both at the repo root, with
no subdirectory support ([docs/adr/0008](../docs/adr/0008-dataform-execution-model.md)'s
correction).

`../workflow_settings.yaml` points `defaultProject` at a placeholder — Dataform 3.x resolves
`@dataform/core` from `dataformCoreVersion` there, no `package.json`/`node_modules` needed, and
`dataform compile` (the CI `dataform-compile` job) succeeds without a live BigQuery connection.
The real project ID is injected at runtime via the release config's `default_database`
(`terraform/dataform.tf`), not by editing this file — see
[docs/adr/0008](../docs/adr/0008-dataform-execution-model.md).

This directory:

- `sources/` — `declaration`s for tables Dataform reads but doesn't manage (the raw external
  table Terraform owns in `terraform/bigquery.tf`).
- `staging/` — one-to-one views that parse/unnest raw source shapes into typed rows, no business
  logic.
- `marts/` — the actual modelled output, with assertions (`climate_risk_warehouse_assertions`).

Runs on Google's schedule (`terraform/dataform.tf`'s release/workflow configs), not from CI or
locally — see [docs/adr/0008](../docs/adr/0008-dataform-execution-model.md).
