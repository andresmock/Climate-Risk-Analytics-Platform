# 10. terraform-ci gains roles/developerconnect.admin

## Status

Accepted, superseded by [ADR-0013](0013-terraform-ci-custom-role.md): terraform-ci no longer
holds `roles/developerconnect.admin`, replaced by scoped permissions in a custom role

## Context

With [ADR-0009](0009-terraform-ci-project-iam-admin-role.md)'s grant applied and the
`depends_on` fix from PR #27 in place, `terraform-apply` got past the previous two failures but
hit a new one creating `google_developer_connect_connection.github` (`terraform/dataform.tf`):

```
Error: Error creating Connection: googleapi: Error 403: Permission
'developerconnect.connections.create' denied on resource
'//developerconnect.googleapis.com/projects/.../locations/europe-west6'
```

Same shape as every prior `terraform-ci` gap recorded in ADR-0006 and ADR-0009: a new resource
type (Developer Connect) was declared in Terraform before `terraform-ci` had any role covering
its API. `dataform.tf` declares two Developer Connect resources —
`google_developer_connect_connection` and `google_developer_connect_git_repository_link` — so the
grant needs to cover both `connections.*` and `gitRepositoryLinks.*` create/update/delete, not
just the one that failed first.

Checked GCP's predefined Developer Connect roles (`gcloud iam roles list
--filter="name:roles/developerconnect*"`): the only one including `connections.create` or
`gitRepositoryLinks.create` is `roles/developerconnect.admin`. The other roles in that family
(`viewer`, `user`, `readTokenAccessor`, `tokenAccessor`, `gitProxyReader`, `gitProxyUser`,
`oauthAdmin`, `oauthUser`, `insightsAdmin`, `connectionHttpProxyWriter`, `serviceAgent`) are all
read-only, proxy/token-access, or OAuth/insights-scoped — none grant resource lifecycle
management. There is no narrower predefined role to reach for here.

## Decision

Grant `terraform-ci` `roles/developerconnect.admin` by hand, same reactive pattern as ADR-0006
and ADR-0009:

```
gcloud projects add-iam-policy-binding project-8f843a0d-a029-4289-a60 \
  --member="serviceAccount:terraform-ci@project-8f843a0d-a029-4289-a60.iam.gserviceaccount.com" \
  --role="roles/developerconnect.admin"
```

## Consequences

- `terraform-ci` can now create/update/delete any Developer Connect connection or git repository
  link in this project, not just the ones this repo's Terraform declares — consistent with the
  existing project-wide-admin-role shape of this identity's other grants (ADR-0006, ADR-0009).
- `google_developer_connect_connection.github` and `google_developer_connect_git_repository_link.warehouse`
  (`terraform/dataform.tf`) can now apply; no config change needed, only the identity's
  permissions.
- Ninth role on `terraform-ci`. Restates the still-open future work from ADR-0006/ADR-0009:
  replace these broad predefined roles with custom roles scoped to actual permissions used, and
  bring `terraform-ci`'s own IAM grants under Terraform management via a separate bootstrap
  identity — each new resource type continuing to surface this reactively is itself evidence for
  doing that cleanup.
