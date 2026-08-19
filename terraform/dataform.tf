# Links this GitHub repo to GCP so Dataform can pull `main` on its own schedule with no CI
# step and no stored credential (see docs/adr/0008). `github_app = "DEVELOPER_CONNECT"` is the
# GitHub App Dataform expects here (distinct from the "FIREBASE" variant used by other Google
# products' Developer Connect integrations).
#
# This connection needs one-time manual GitHub App authorization after apply: run
# `terraform output developer_connect_installation_state` and visit the `action_uri` it
# contains. Only once the connection reaches COMPLETE can the Dataform repository resource
# (added in a follow-up PR) reference `google_developer_connect_git_repository_link.warehouse`
# via `git_remote_settings.git_repository_link` — that's why this PR stops here.
resource "google_developer_connect_connection" "github" {
  provider      = google-beta
  location      = var.region
  connection_id = "climate-risk-analytics-platform"

  # Without these, Terraform has no edge to either prerequisite (nothing here references them)
  # and can start creating the connection before developerconnect.googleapis.com has finished
  # enabling/propagating (SERVICE_DISABLED), or before Developer Connect's own service agent can
  # create its backing Secret Manager secret (SECRET_CREATE_PERMISSION_MISSING, see iam.tf).
  depends_on = [
    google_project_service.required["developerconnect.googleapis.com"],
    google_project_iam_member.devconnect_agent_manages_secrets,
  ]

  github_config {
    github_app = "DEVELOPER_CONNECT"
  }
}

resource "google_developer_connect_git_repository_link" "warehouse" {
  provider               = google-beta
  location               = var.region
  parent_connection      = google_developer_connect_connection.github.connection_id
  git_repository_link_id = "climate-risk-analytics-platform"
  clone_uri              = "https://github.com/andresmock/Climate-Risk-Analytics-Platform.git"
}

output "developer_connect_installation_state" {
  description = "Visit installation_state.action_uri once after apply to complete GitHub App authorization."
  value       = google_developer_connect_connection.github.installation_state
}
