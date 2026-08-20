# 14. Scheduled drift detection for Terraform state

## Status

Accepted

## Context

[ADR-0012](0012-terraform-apply-moves-local-only.md) retired `terraform-apply` from CI: applying
against the real project is now a manual, local step, run after a PR merges to `main`. That ADR
named the resulting gap directly: a merged PR that touches `terraform/` no longer updates the
real project by itself, and `terraform-plan`'s PR-comment output is the only signal that infra
changed — nothing flags a merged-but-unapplied PR after the fact. ADR-0012 proposed closing this
with a scheduled drift-detection job but didn't build it.

## Decision

Add a scheduled job, `terraform-drift` (`.github/workflows/terraform-drift.yml`), running daily
and on manual `workflow_dispatch`. It authenticates as the existing `terraform-plan` identity
([ADR-0007](0007-least-privilege-terraform-plan-identity.md)) — already read-only, already scoped
for exactly this kind of check — and runs `terraform plan -detailed-exitcode` against `main`. Exit
code `2` (pending changes) or `1` (error) fails the job; exit code `0` (no changes) passes
silently. A failed run shows up red in the Actions tab; there's no other notification channel
wired up.

Deliberately reuses `terraform-plan` rather than minting a new identity — this is the same
read-only capability the PR-triggered job already has, just invoked on a schedule instead of a
pull request event.

## Consequences

- A merged-but-unapplied `terraform/` change now surfaces within 24 hours instead of silently
  persisting until someone happens to run `apply` or `plan` locally.
- Still no auto-remediation — the job only detects and flags drift; a human still runs `apply`
  locally to resolve it, same as before.
- One more scheduled job billed against Actions minutes, negligible at this repo's size.
