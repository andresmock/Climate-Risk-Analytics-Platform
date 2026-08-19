# 11. Grant Developer Connect's service agent secretmanager.admin, managed by Terraform

## Status

Accepted

## Context

With ADR-0010's grant applied, `terraform-apply` got past `developerconnect.connections.create`
and hit a third failure creating `google_developer_connect_connection.github`:

```
Error 400: The service account service-958921262344@gcp-sa-devconnect.iam.gserviceaccount.com
could not create a secret: generic::permission_denied: Permission
'secretmanager.secrets.create' denied on resource (or it may not exist).
reason: SECRET_CREATE_PERMISSION_MISSING
```

`service-<project_number>@gcp-sa-devconnect.iam.gserviceaccount.com` is Developer Connect's own
Google-managed service agent (P4SA), not `terraform-ci`. It needs to create a Secret Manager
secret to store this connection's GitHub App installation credentials. Google's Console "Enable
API" flow grants this agent `roles/secretmanager.admin` by default as part of enabling the API;
enabling the API via Terraform (`google_project_service`, as this repo does) does not trigger
that default grant, so it has to be declared explicitly. Checked predefined Secret Manager roles
(`gcloud iam roles describe ... | grep secrets.create`): `roles/secretmanager.admin` is the only
one including `secretmanager.secrets.create`.

This is a materially different grant from ADR-0009/ADR-0010, worth calling out given the standing
concern (also recorded in those ADRs) about how many broad admin roles `terraform-ci` has
accumulated: this grant adds no power to `terraform-ci` at all. It's a standard, Google-documented
bootstrap permission for Developer Connect's own service robot to do its one documented job
(store this connection's credentials), scoped to that P4SA identity, not to any identity this
repo's workflows run as.

## Decision

Manage it as a real `google_project_iam_member` resource (`terraform/iam.tf`,
`devconnect_agent_manages_secrets`) instead of a manual `gcloud` grant. This is possible because
`terraform-ci` already holds `roles/resourcemanager.projectIamAdmin` (ADR-0009), so it can set
this project-level binding itself — directly delivering the "bring `terraform-ci`'s IAM grants
under Terraform management" item ADR-0006 and ADR-0009 both listed as future work, for at least
this one grant.

Added explicit `depends_on` from `google_developer_connect_connection.github` to both this
resource and the API-enablement resource (`terraform/dataform.tf`), rather than relying on
Terraform to infer the ordering — the connection resource doesn't reference either by attribute,
so without `depends_on` Terraform has no edge and can (and did, twice now: SERVICE_DISABLED per
the fix in PR #27, then this) attempt to create the connection before a prerequisite is ready.

## Consequences

- No change to `terraform-ci`'s own role list — this grant targets a different identity
  entirely.
- `google_developer_connect_connection.github` can now apply; this grant is version-controlled
  and reviewed via this PR's diff, not run by hand and documented after the fact.
- Established a reusable pattern for any future Google-managed service agent grant this repo
  needs: prefer a Terraform-managed `google_project_iam_member`/`google_service_account_iam_member`
  over a manual `gcloud` step whenever `terraform-ci` already holds sufficient permission to
  create the binding itself, and always wire the dependent resource's `depends_on` to it
  explicitly rather than assuming apply ordering.
