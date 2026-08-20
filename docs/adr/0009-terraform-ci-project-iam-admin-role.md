# 9. terraform-ci gains roles/resourcemanager.projectIamAdmin

## Status

Accepted, superseded by [ADR-0013](0013-terraform-ci-custom-role.md): terraform-ci no longer
holds `roles/resourcemanager.projectIamAdmin` or any project-level `setIamPolicy` permission

## Context

The Dataform work (ADR-0008) added this repo's first `google_project_iam_member` resource
(`dataform_runtime_runs_queries`, granting `roles/bigquery.jobUser` project-wide since BigQuery
query-job creation has no dataset-scoped equivalent). CI run #80 failed applying it:

```
Error retrieving IAM policy for project "...": googleapi: Error 403: The caller does not have
permission, forbidden
```

`terraform-ci`'s roles, as recorded in [ADR-0006](0006-terraform-ci-footprint-update.md), are all
resource-scoped `*.admin` grants (`bigquery.admin`, `run.admin`, `storage.admin`, etc.). None of
them cover `resourcemanager.projects.getIamPolicy`/`setIamPolicy` — the permissions needed to
read-modify-write the *project's* IAM policy itself, independent of which role is being granted.
This gap was already flagged as unresolved debt in ADR-0006's Consequences section.

## Decision

Grant `terraform-ci` `roles/resourcemanager.projectIamAdmin` by hand, the same reactive,
undocumented-until-now pattern ADR-0006 already recorded for this identity's other six roles:

```
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="serviceAccount:terraform-ci@<PROJECT_ID>.iam.gserviceaccount.com" \
  --role="roles/resourcemanager.projectIamAdmin"
```

No narrower predefined role covers project-level `setIamPolicy`; a custom role scoped to just
`resourcemanager.projects.getIamPolicy`/`setIamPolicy` was considered but not built, consistent
with ADR-0006 deferring the broader custom-roles cleanup rather than doing it piecemeal per grant.

## Consequences

- `terraform-ci` can now grant or revoke *any* IAM role at the project level, not just the
  specific bindings this repo's Terraform declares — a further widening of the blast radius
  ADR-0006 already flagged for this identity (public repo, WIF trust scoped only to the
  repository).
- `google_project_iam_member.dataform_runtime_runs_queries` (`terraform/iam.tf`) can now apply
  cleanly; no config change was needed, only the identity's permissions.
- This ADR extends ADR-0006's role list; ADR-0006's Status line should be read alongside this one
  for the current full picture, per [ADR-0001](0001-record-architecture-decisions.md)'s
  supersede-don't-edit convention.
- Restates ADR-0006's still-open future work: replace these broad predefined roles (now eight)
  with custom roles scoped to actual permissions used, and bring `terraform-ci`'s own IAM grants
  under Terraform management via a separate bootstrap identity.
