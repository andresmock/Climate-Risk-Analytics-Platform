# 6. terraform-ci footprint update: apply trigger and IAM roles

Date: 2026-08-17

## Status

Accepted, role list superseded by [ADR-0009](0009-terraform-ci-project-iam-admin-role.md)

## Context

Bringing up the ingestion Cloud Run Job, Cloud Scheduler job, and their IAM (ADR-0005) surfaced two places where [ADR-0004](0004-terraform-plan-apply-in-ci.md) no longer matches reality:

**Apply trigger.** ADR-0004 recorded `terraform-apply` as running only via manual `workflow_dispatch`, with a note that once the repo went public, the required-reviewer environment protection would become available and should replace that manual trigger with auto-apply-on-merge. The repo has since gone public and that follow-up already happened (`ci.yml`'s `changes`/`terraform-apply` jobs): `terraform-apply` now runs automatically on a push to `main` that touches `terraform/**`, gated by the `terraform-apply` environment's required-reviewer rule, with `workflow_dispatch` kept as a manual fallback. ADR-0004's own text was never updated to say so.

**`terraform-ci`'s roles.** ADR-0004 listed three roles (`storage.admin`, `bigquery.admin`, `serviceusage.serviceUsageAdmin`) and explicitly flagged that the list would need extending as new resource types were declared. It has been extended four times since — once per new resource type (Artifact Registry, Cloud Run, Cloud Scheduler, service-account IAM) — each time by running `gcloud projects add-iam-policy-binding` by hand against the real project, immediately after a `terraform apply` failure named the missing permission. None of those grants were recorded anywhere until this ADR. The actual current policy (`gcloud projects get-iam-policy`, filtered to `terraform-ci`):

```
roles/artifactregistry.admin
roles/bigquery.admin
roles/cloudscheduler.admin
roles/iam.serviceAccountAdmin
roles/run.admin
roles/serviceusage.serviceUsageAdmin
roles/storage.admin
```

## Decision

Record both changes as facts, without re-litigating them — the apply-trigger change was already the intended future state per ADR-0004 itself, and the role grants were necessary for the infrastructure in ADR-0005 to exist at all. This ADR supersedes ADR-0004 only on these two specific points; ADR-0004's WIF-based auth, the plan-as-PR-comment flow, and the retirement of local applies are unchanged and still in effect.

No role changes are made as part of this ADR. See Consequences for why the current grants are flagged as debt rather than fixed now.

## Consequences

- ADR-0004's Status line is updated to point here for the apply-trigger and role-list specifics; its body is left as the historical record of the original reasoning, per [ADR-0001](0001-record-architecture-decisions.md)'s supersede-don't-edit convention.
- `terraform-ci` now holds seven broad, project-wide predefined `*.admin`/`*Admin` roles rather than fine-grained ones. In particular, `roles/iam.serviceAccountAdmin` combined with `roles/run.admin` and `roles/artifactregistry.admin` lets `terraform-ci` grant `actAs`/`serviceAccountUser` on *any* service account in the project and then deploy Cloud Run resources running as that identity — not just the ones Terraform is meant to manage (`ingestion_runtime`, `ingestion_deploy`, `scheduler_invoker`). Since the repo is public and the WIF trust condition is scoped only to the repository, this is the real blast radius of anything that can trigger a workflow run here, not a hypothetical one.
- The pattern of granting roles by hand, reactively, off of a failed `terraform apply`'s error message, has no PR review and no record until written up after the fact (as happened here). This is a gap in the audit trail the rest of the project otherwise maintains (ADR-0001, ADR-0003).
- **Future work, not undertaken here:**
  - Replace the broad predefined roles above with custom roles scoped to the specific permissions `terraform-ci` actually calls, rather than full `*.admin` grants — e.g. it needs to manage IAM policies only on the three ingestion-related service accounts, not `serviceAccounts.setIamPolicy` project-wide.
  - Bring `terraform-ci`'s own project-level IAM grants under Terraform management (via `google_project_iam_member`), using a separate, more-privileged, rarely-used bootstrap identity to apply just that layer — so the next new resource type extends `terraform-ci`'s roles through a reviewed PR diff instead of an undocumented `gcloud` command run by hand.
  - Periodically re-run the `gcloud projects get-iam-policy` query above and diff it against what's documented, until the previous bullet makes that check redundant.
