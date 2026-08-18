# 8. Dataform repository, execution, and scheduling model

Date: 2026-08-18

## Status

Accepted

## Context

Ingestion is live (see `src/ingestion/README.md`, [ADR-0005](0005-ingestion-scheduling-and-deploys.md)):
a Cloud Run Job lands raw Open-Meteo JSON in GCS every 6 hours, and `climate_risk_raw.forecasts`
(an external BigQuery table, `terraform/bigquery.tf`) reads it directly. `dataform/` is still a
skeleton — `workflow_settings.yaml` points at a placeholder project, `definitions/` is empty — but
the prerequisite raw data now exists, so it's time to make Dataform live. The `climate_risk` and
`climate_risk_assertions` datasets it will write to already exist, per [ADR-0002](0002-initial-architecture-and-technology-stack.md).

Three things need settling: how Dataform gets this repo's SQLX code into GCP, how a compiled
release actually runs against BigQuery, and what identity/schedule drives it — mirroring the three
questions ADR-0005 settled for ingestion.

## Decision

**Google Cloud Dataform, linked to this GitHub repo via Developer Connect**, not a stored GitHub
PAT and not a CI push step. Three ways to get SQLX code from `main` into GCP were considered:

- A GitHub PAT stored in Secret Manager, referenced by `google_dataform_repository`'s
  `git_remote_settings.authentication_token_secret_version`. Simplest to express purely in
  Terraform, but it's a long-lived credential this repo would then own, cutting against the
  "no stored key" precedent `ingestion-deploy` set (WIF-based, ADR-0005).
- No git link at all: a WIF-based `dataform-deploy` identity, mirroring `ingestion-deploy`, pushes
  compiled code into Dataform's own internal repo via API on every merge to `main` that touches
  `dataform/`. No stored secret, but it needs custom CI logic (workspace write/commit calls) and
  creates a second "main" (GitHub's and Dataform's internal one) that has to stay in sync.
- **Developer Connect** (`google_developer_connect_connection` + `google_developer_connect_git_repository_link`,
  referenced from `google_dataform_repository.git_remote_settings.git_repository_link`): a
  one-time manual GitHub App authorization (visiting the connection resource's `action_uri`
  output) links the repo. After that, Dataform pulls `main` itself — no CI step, no secret this
  repo stores or rotates. The one-time manual step is the same category of bootstrap this repo
  already accepts for the GitHub Actions WIF pool (`terraform/README.md`).

Developer Connect wins: it gets the "no CI step, no stored key" property of the internal-repo
approach with the "Dataform just tracks `main`" simplicity of the PAT approach, at the cost of one
manual console step instead of zero.

**No new Cloud Scheduler resource.** Ingestion needed Cloud Scheduler because a Cloud Run Job has
no scheduling of its own. `google_dataform_repository_workflow_config` has a built-in
`cron_schedule` — Dataform triggers its own runs. So there's no `dataform-scheduler` identity to
mirror `ingestion-scheduler`.

**Two Dataform-native resources drive execution**, both created alongside the repository in
`terraform/dataform.tf`:
- `google_dataform_repository_release_config`: recompiles `git_commitish = "main"` on its own
  `cron_schedule`, producing a compilation result. `code_compilation_config.default_database` is
  set to `var.project_id` here — **not** by editing the committed `workflow_settings.yaml`, which
  keeps its placeholder project. `dataform compile` (the CI `dataform-compile` job) doesn't need a
  live project to succeed, so this keeps the real project ID out of git entirely, the same
  property `terraform.tfvars` already has via `.gitignore`.
- `google_dataform_repository_workflow_config`: executes the release config's latest compilation
  result on its own `cron_schedule`, offset after ingestion's so a run always sees freshly-landed
  data.

**`dataform-runtime`, a new least-privilege service account** (`terraform/iam.tf`), set as both
the repository's `service_account` (default execution identity) and the workflow config's:
- `roles/bigquery.dataViewer` on `climate_risk_raw` (read the raw external table).
- `roles/bigquery.dataEditor` on `climate_risk` and `climate_risk_assertions` (write modelled
  output and assertion results).
- `roles/bigquery.jobUser`, **at the project level** — this is a deliberate exception to how every
  other SA this repo manages is scoped. `ingestion-runtime`, `ingestion-deploy`, and
  `scheduler-invoker` all hold only resource-scoped bindings; BigQuery query-job creation has no
  dataset-scoped equivalent to `jobUser`, so this is the narrowest grant that lets
  `dataform-runtime` actually run queries.
- `roles/iam.serviceAccountTokenCreator`, granted to Dataform's Google-managed service agent
  (`service-<PROJECT_NUMBER>@gcp-sa-dataform.iam.gserviceaccount.com`) on `dataform-runtime` —
  the same shape as the existing `scheduler_agent_mints_invoker_tokens` grant for
  `ingestion-scheduler`. Included defensively; **verify at first apply** whether Dataform's
  scheduled workflow invocations actually require it, since it wasn't confirmed against a live
  project before this ADR was written.

**`terraform-ci` and `terraform-plan` need extended read/write coverage for the new resource
types**, granted by hand (same as their own project-level roles already are, per ADR-0007):
`terraform-ci` needs `roles/dataform.admin` and `roles/developerconnect.admin` to create these
resources. `terraform-plan`'s existing `roles/viewer` should already cover reading them — ADR-0007
established that Viewer "covers read/diff access across resource types as Terraform starts
managing new ones" without per-resource-type grants — but this should be smoke-tested the same way
ADR-0007 smoke-tested `getIamPolicy` coverage, since Developer Connect and Dataform are newer
services that may not be fully covered.

Because Developer Connect's GitHub App authorization is an out-of-band manual step, this lands in
two applies: first the connection/link (after which the user visits `action_uri` once), then the
Dataform repository/release/workflow configs that reference the now-`COMPLETE` connection.

## Consequences

- Dataform code changes ship automatically: merge to `main`, and the next `release_config` cron
  tick picks it up — no deploy step, unlike ingestion's CI-driven image push.
- One more manual, out-of-band bootstrap step (GitHub App authorization) alongside the WIF pool
  and `terraform-ci`/`terraform-plan`'s own project roles — none of these are visible in this
  repo's Terraform config.
- `dataform-runtime` breaks this repo's so-far-consistent "no project-level grants for
  service-specific SAs" pattern, narrowly, because BigQuery's job model requires it.
- The `iam.serviceAccountTokenCreator` grant for Dataform's service agent is unverified against a
  live project as of this ADR — the first scheduled workflow invocation's success or failure is
  the actual test.
- Release and workflow cadences (proposed: daily recompile, workflow runs offset ~30 minutes after
  ingestion's 6-hourly ticks) are starting guesses, not measured choices, same as ingestion's
  6-hour cadence in ADR-0005 — easy to retune once there's real data on compile frequency needs and
  data-freshness lag.
