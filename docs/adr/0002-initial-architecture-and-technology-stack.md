# 2. Initial architecture and technology stack

Date: 2026-07-28

## Status

Accepted

## Context

The first milestone (see [docs/vision.md](../vision.md)) is to ingest and analyse public weather data from [Open-Meteo](https://open-meteo.com/) on Google Cloud Platform. As an open-source reference implementation intended to demonstrate data engineering practice, the stack needs to balance:

- low/no cost for a low-traffic, low-volume workload run by a single maintainer
- recognisable, industry-standard tooling over GCP-proprietary conveniences, so the skills demonstrated transfer to a reader's own context
- room to grow into the long-term vision (additional data sources, modelling, ML) without a rewrite

## Decision

**Compute / orchestration:** Cloud Run, running an explicit, hand-written Dockerfile (not Google's buildpacks, not Cloud Functions). Cloud Run runs containers natively; owning the Dockerfile keeps the runtime contract explicit, gives local/prod parity, and demonstrates containerization directly rather than hiding it behind `gcloud run deploy --source .`. Cloud Scheduler triggers ingestion runs on a schedule.

**Storage:** A bronze/gold split — raw Open-Meteo responses land in Google Cloud Storage (GCS) unmodified, then get loaded and modelled in BigQuery. This is the standard data-lake-plus-warehouse pattern rather than loading directly into BigQuery, which keeps a durable, replayable copy of the raw source.

**Transformation:** [Dataform](https://cloud.google.com/dataform), BigQuery's native SQLX-based transformation tool. Chosen over dbt for tighter native BigQuery integration and lower operational surface for a solo-maintained project; chosen over hand-written SQL/Python for built-in dependency management, testing (assertions), and documentation generation.

**Infrastructure as code:** Terraform. All GCP resources (buckets, BigQuery datasets, Cloud Run service, Cloud Scheduler jobs, IAM) are declared in `terraform/` rather than created via console or ad hoc `gcloud` commands.

## Consequences

- The stack is entirely serverless: no Kubernetes cluster, no always-on compute to manage or pay for. Cost scales with actual usage (which, for a scheduled low-frequency ingestion job, is expected to stay within GCP's free tier).
- A Dockerfile is a real artifact in the repo that needs maintaining (base image updates, multi-stage build, non-root user) — a deliberate small cost in exchange for demonstrating the skill explicitly rather than relying on invisible buildpacks.
- Dataform ties transformation to BigQuery specifically; if the project ever needed a warehouse-agnostic transformation layer, migrating to dbt would be a rewrite. Given BigQuery is also the chosen warehouse, this coupling is acceptable.
- This scaffolding pass creates only skeleton Terraform/Dataform/Dockerfile configuration with no live GCP project behind it yet. Provisioning the actual GCP project, remote Terraform state backend, and live Dataform/BigQuery connection is deferred to the ingestion milestone itself.
