# 13. Replace terraform-ci's broad admin roles with a scoped custom role

## Status

Accepted, supersedes the role-list parts of [ADR-0006](0006-terraform-ci-footprint-update.md),
[ADR-0009](0009-terraform-ci-project-iam-admin-role.md), and
[ADR-0010](0010-terraform-ci-developer-connect-admin-role.md)

## Context

[ADR-0012](0012-terraform-apply-moves-local-only.md) closed the specific, concrete risk this
session surfaced — a broadly-privileged identity reachable by a GitHub-triggered CI run on a
public repo — by revoking `terraform-ci`'s CI trust entirely. That ADR deliberately left
`terraform-ci`'s role list untouched, flagging the "future work" both ADR-0006 and ADR-0009 had
already deferred: replacing its predefined `*.admin`/`*Admin` roles
(`artifactregistry.admin`, `bigquery.admin`, `cloudscheduler.admin`, `iam.serviceAccountAdmin`,
`run.admin`, `serviceusage.serviceUsageAdmin`, `storage.admin`, `developerconnect.admin`) and
`resourcemanager.projectIamAdmin` with something scoped to what this repo's Terraform actually
uses. With CI no longer able to invoke this identity at all, that cleanup is no longer closing a
live attack path — it's ordinary least-privilege hygiene (e.g. against a compromised local
machine or personal Google account) — but still worth doing now that apply is proven to work
locally and iteration is fast.

One permission needed a different treatment than the rest: `roles/resourcemanager.projectIamAdmin`
is already narrowly scoped to project-level IAM policy management specifically — wrapping it in a
custom role wouldn't reduce its risk, since any identity that can set project-level IAM policy can
grant itself anything, regardless of how that permission is packaged. The two resources that
needed it (`dataform_runtime_runs_queries`, `devconnect_agent_manages_secrets`) were originally
made Terraform-managed by ADR-0011 specifically to keep them PR-reviewable while `terraform-apply`
still ran in CI. That reasoning no longer applies post-ADR-0012 (apply is human-run either way), so
both revert to manual grants — the same out-of-band pattern already used for `terraform-ci`'s own
roles since ADR-0004 — and `terraform-ci` drops project-level `setIamPolicy` entirely.

That drop has a structural consequence worth naming explicitly: binding *any* project-level role —
including the new custom one below — requires `resourcemanager.projects.setIamPolicy`. Once
`terraform-ci` no longer holds that permission at all, it cannot bind project-level roles to
itself (or anyone) through Terraform, ever, regardless of what other permissions it accumulates in
the future. Only the custom role's *definition* (`google_project_iam_custom_role`, needing just
`roles/iam.roleAdmin`) is Terraform-managed; binding that role to `terraform-ci` remains manual.

## Decision

Define a single custom role, `terraform_ci` (`terraform/iam.tf`), containing exactly the
permissions this repo's Terraform resources use across their full lifecycle
(create/read/update/delete), verified against `gcloud iam list-testable-permissions` on this
project's actual live resources rather than assumed from documentation. Deliberately excludes
`bigquery.jobs.*` (that's `dataform-runtime`'s separate, already-scoped `bigquery.jobUser` grant)
and any `resourcemanager.projects.*` permission.

Two permissions are flagged as likely-but-not-certainly necessary rather than fully verified:
`cloudscheduler.jobs.fullView` (Scheduler's plain `get` may return a redacted view; `fullView`
sits alongside `get` in `roles/cloudscheduler.admin`) and `run.operations.get`/
`developerconnect.operations.get` for polling long-running create operations (Developer Connect's
connection creation took 20+ seconds in run #80, confirming this one is likely load-bearing;
Cloud Run's is analogous but unconfirmed against a real slow create). A missing permission here
surfaces immediately as a clear `PERMISSION_DENIED` on `plan`/`apply` — not silent
misbehavior — so left in rather than omitted, to be corrected via a fast local iteration if wrong.

`terraform-ci`'s existing broad roles are revoked, and the new custom role bound in its place, by
hand — same manual, out-of-band pattern as every prior grant to this identity (ADR-0004 onward).
The two reverted `google_project_iam_member` resources become manual grants as well.

## Consequences

- `terraform-ci` can no longer touch any GCP resource type this repo's Terraform doesn't declare
  (previously true in principle only for the resource-scoped roles; now true across the board,
  including Service Usage, IAM, and Developer Connect, which the old `*.admin` roles left
  unnecessarily broad).
- `terraform-ci` can never again grant itself (or anyone) a project-level role through Terraform,
  structurally — not because of a policy decision that could be reversed by a future PR, but
  because it holds no `resourcemanager.projects.setIamPolicy` permission at all.
- One more moving part: a custom role definition to keep in sync as new resource types get added,
  instead of reaching for an existing predefined role. Same "future work" shape as before —
  extending it requires a PR touching `terraform/iam.tf`'s permission list, reviewable in the diff
  — but no longer requires a reactive `gcloud` grant against production first, the way the
  original seven roles in ADR-0006 were each discovered.
- If any permission above turns out to be missing or unnecessary once exercised against a real
  `apply` (particularly the two flagged as uncertain), fixing it is a fast local iteration now
  that ADR-0012 made apply human-run — no CI round-trip required.

**Correction (found applying this ADR):** the permission audit covered only resources this
repo's Terraform *declares*, missing that `terraform-ci` also needs to read/write its own remote
state — the GCS state bucket isn't itself a declared resource. The old `roles/storage.admin`
covered this as a side effect; the custom role's `storage.buckets.*` list didn't, since that's
bucket-level metadata, not object-level state-file access. Fixed the same way ADR-0007 already
handles this for `terraform-plan`: an unconditional `roles/storage.objectAdmin` binding scoped to
just the state bucket (`gcloud storage buckets add-iam-policy-binding`), granted by hand, not
added to the project-wide custom role.
