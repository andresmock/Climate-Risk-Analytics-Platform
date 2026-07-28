# 3. Engineering workflow, CI, and repository visibility

Date: 2026-07-28

## Status

Accepted

## Context

As an open-source reference implementation, the process around the code — how it's tested, reviewed, and released — matters as much as the code itself: it's what makes the project trustworthy and maintainable, not just functional. This needed to be settled before substantial code was written, so that history and process are consistent from the first real commit rather than retrofitted.

## Decision

**Git workflow:** Trunk-based development. Short-lived feature branches, merged to `main` via pull request (even as a solo maintainer, to keep a reviewable history), using [Conventional Commits](https://www.conventionalcommits.org/) for commit messages. Commits and PR descriptions are written to stand on their own as engineering rationale; no AI co-authorship trailer is added to commits, since the repo is meant to represent the maintainer's own engineering decisions and judgment.

**CI (`.github/workflows/ci.yml`):** Every PR runs, at minimum:
- `lint-and-test`: `ruff check`, `ruff format --check`, `pytest` via `uv`
- `terraform-check`: `terraform fmt -check` and `terraform validate`
- `dataform-compile`: `dataform compile` against the Dataform project
- `docker-build`: builds the ingestion service's Dockerfile as a smoke test

`terraform-check` and `dataform-compile` run against local state / no live connection, since no GCP project exists yet at the time of this scaffold — see [ADR-0002](0002-initial-architecture-and-technology-stack.md). `terraform plan` against a real project, live Dataform warehouse compilation, and pushing/deploying the built container image are deferred until the GCP project is provisioned, and will be added to CI at that point rather than faked now.

**Data quality:** Dataform's built-in assertions (uniqueness, not-null, custom SQL checks) cover the warehouse layer; `pytest` covers the Python ingestion code. No additional validation framework (e.g. Great Expectations) is introduced unless a concrete gap appears.

**Documentation:** A concise public `README.md` plus `docs/adr/` for decision history and `docs/vision.md` for the project's motivation and long-term direction. No separate docs site for now.

**Repository visibility:** The repository stays **private** until the first milestone — a working ingestion pipeline landing weather data in BigQuery — is complete. GitHub preserves full commit history and original commit timestamps when a repository's visibility is flipped from private to public, so nothing is lost by waiting: the incremental development story is still visible once the repo goes public. This avoids anyone finding an empty scaffold with no working functionality behind it.

## Consequences

- CI will initially validate structure and static correctness only (lint, unit tests, `terraform validate`, `dataform compile`, `docker build`), not live deployment — the workflow file and this ADR both call that out explicitly so it doesn't read as broken or incomplete CI.
- Going public is a one-way, deliberate step tied to a concrete milestone rather than a calendar date.
- Because commits avoid AI attribution, any future contributor (including the maintainer's own later self) should not infer from the commit history whether or how AI assistance was used — that context lives in `AGENT.md` (gitignored, not part of the public project) instead.
