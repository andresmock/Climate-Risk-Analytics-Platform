# 12. Retire terraform-apply from CI; apply moves to local-only, human-run

## Status

Accepted, supersedes the apply-in-CI parts of [ADR-0004](0004-terraform-plan-apply-in-ci.md) and
[ADR-0006](0006-terraform-ci-footprint-update.md)

## Context

`terraform-ci`'s role list has grown by five broad, project-wide `*.admin`/`*Admin`/`*IamAdmin`
grants since ADR-0006 recorded the first seven (`roles/resourcemanager.projectIamAdmin`,
ADR-0009; `roles/developerconnect.admin`, ADR-0010), each added reactively while landing the
Dataform/Developer Connect work in ADR-0008. ADR-0006 already named the resulting risk directly:
this repo is public, `terraform-ci`'s WIF trust condition is scoped only to the repository (not
to a branch, environment, or reviewer), and `roles/iam.serviceAccountAdmin` combined with the
resource-admin roles already let `terraform-ci` reach well past the specific resources this
repo's Terraform declares — "not a hypothetical" blast radius, in ADR-0006's own words, for
*anything that can trigger a workflow run here*.

`roles/resourcemanager.projectIamAdmin` (ADR-0009) makes that concrete rather than abstract: it
lets `terraform-ci` grant *any* role to *any* principal at the project level, including to
itself. ADR-0011 used exactly that power — deliberately, to keep an IAM grant reviewable in a PR
diff instead of another untracked `gcloud` command — to let `terraform-ci` grant
`roles/secretmanager.admin` to Developer Connect's service agent, which manages the Secret
Manager secret holding the GitHub OAuth token from the Developer Connect connection's
authorization step. That token carries the GitHub permissions of whoever authorizes the
connection. The combination means: a same-repo PR that reaches `terraform-apply` (auto-triggered
on push to `main`, gated only by a required-reviewer *approval click*, not by any reduction in
`terraform-ci`'s actual credentials) can self-grant read access to that secret and, through it,
act on GitHub as whoever authorized the connection. The required-reviewer gate protects against
an *unreviewed* apply; it does nothing once `terraform-ci`'s standing credentials are the thing
being relied on for the trust boundary, since the gate only decides whether the run happens, not
what the identity behind it can do once it does.

Trimming `terraform-ci`'s roles down to custom, narrowly-scoped ones (the "future work" both
ADR-0006 and ADR-0009 deferred) would reduce this but not eliminate it — some project-level
IAM-granting capability is unavoidable for a fully automated `apply`, and this session's pattern
(four new grants across four PRs, each discovered only by a failed live apply) shows the reactive
model keeps finding new resource types that need it.

## Decision

Retire `terraform-apply` from CI entirely. `terraform apply` against the real project is now run
locally by a human, authenticating by impersonating the existing `terraform-ci` identity (its
role set is unchanged — this decision removes *who can invoke it*, not what it can do).
`terraform plan` stays in CI exactly as it is: read-only, using the separate least-privilege
`terraform-plan` identity from ADR-0007, PR-triggered, posts the plan as a PR comment for review
before a human runs the real apply.

**`.github/workflows/ci.yml`:**
- Removed the `terraform-apply` job and the `changes` job that only existed to gate it (the
  push-to-main-touching-`terraform/**` trigger).
- `terraform-check` (fmt/validate, no credentials) and `terraform-plan` (unchanged) remain.

**IAM, applied by hand (same manual, out-of-band pattern already used for `terraform-ci`'s own
bootstrap per ADR-0004/0006 — this repo has never managed `terraform-ci`'s own grants through its
own Terraform):** revoke `terraform-ci`'s WIF trust binding so no GitHub Actions run can assume
it anymore, and grant the human's own GCP principal `roles/iam.serviceAccountTokenCreator` on
`terraform-ci` so local applies can proceed by impersonating the same, already-scoped identity.

Reusing `terraform-ci` rather than minting a new local-apply identity keeps its existing,
already-correct role set intact and keeps its actions distinguishable in audit logs from the
human's own identity elsewhere — only its trust binding changes. Renaming it despite it no longer
running in CI would mean recreating the service account and re-granting every role; not done
here, left as optional future cleanup.

Local apply then proceeds by authenticating as an impersonated identity for `terraform-ci` and
running `terraform init`/`apply` with the same backend config and `-var` values the old CI job
used.

## Consequences

- `terraform-ci`'s credentials are no longer reachable from any GitHub Actions trigger — the
  specific blast radius ADR-0006 flagged (and ADR-0011's Secret Manager grant made concrete) is
  closed regardless of how many more broad roles get added to this identity in the future.
- No config change was needed on `terraform-ci`'s roles themselves; they're unchanged and still
  as broad as ADR-0006/0009/0010 recorded. The custom-roles cleanup those ADRs deferred is still
  worth doing eventually, but is no longer a live security boundary — it's ordinary
  least-privilege hygiene on an identity only a human can now invoke.
- No more auto-apply-on-merge: a merge to `main` that changes `terraform/**` no longer updates
  the real project by itself. `terraform-plan`'s PR-comment output is the only signal that
  infra changed until a local `apply` is run — a merged PR can sit un-applied with no automated
  flag for it. Closed by [ADR-0014](0014-terraform-drift-detection.md)'s scheduled drift-detection
  job.
- The `terraform-apply` GitHub Environment (required-reviewer protection) and the
  `GCP_TF_SERVICE_ACCOUNT` repository variable become unused. Not removed by this change (both
  are GitHub repo settings, not files in this repo) — safe to delete for tidiness whenever
  convenient.
- `ingestion-deploy`'s image-deploy path (ADR-0005) is unaffected: it's already decoupled from
  `terraform-apply` and uses its own separate, narrowly-scoped identity.
