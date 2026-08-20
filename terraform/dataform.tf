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

  # Guards against creating the connection before the API finishes enabling (SERVICE_DISABLED).
  # The other prerequisite, the devconnect agent's Secret Manager grant, is now a manual step
  # with no Terraform resource to depend on (see docs/adr/0013) — it must exist before apply.
  depends_on = [google_project_service.required["developerconnect.googleapis.com"]]

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

# The repository itself: pulls `main` via the Developer Connect link above. `service_account`
# here is the default execution identity for interactive workspaces; the release/workflow
# configs below set their own (same SA) for scheduled runs. See docs/adr/0008.
resource "google_dataform_repository" "warehouse" {
  provider = google-beta
  region   = var.region
  name     = "climate-risk-analytics-platform"

  git_remote_settings {
    url                 = google_developer_connect_git_repository_link.warehouse.clone_uri
    default_branch      = "main"
    git_repository_link = google_developer_connect_git_repository_link.warehouse.name
  }

  service_account = google_service_account.dataform_runtime.email

  depends_on = [google_project_service.required["dataform.googleapis.com"]]
}

# Recompiles `main` daily, producing a compilation result the workflow config below executes.
# `default_database` is set here, not in the committed workflow_settings.yaml (which
# keeps its placeholder project) — keeps the real project ID out of git. Cadence is a starting
# guess, not measured, same as ingestion's 6-hour cadence (docs/adr/0005) — easy to retune.
resource "google_dataform_repository_release_config" "warehouse" {
  provider   = google-beta
  region     = var.region
  repository = google_dataform_repository.warehouse.name
  name       = "daily"

  git_commitish = "main"
  cron_schedule = "0 2 * * *"
  time_zone     = "UTC"

  code_compilation_config {
    default_database = var.project_id
  }
}

# Executes the release config's latest compilation result, offset 30 minutes after each of
# ingestion's 6-hourly ticks (terraform/scheduler.tf) so a run always sees freshly-landed data.
resource "google_dataform_repository_workflow_config" "warehouse" {
  provider       = google-beta
  region         = var.region
  repository     = google_dataform_repository.warehouse.name
  release_config = google_dataform_repository_release_config.warehouse.id
  name           = "warehouse"

  cron_schedule = "30 0,6,12,18 * * *"
  time_zone     = "UTC"

  invocation_config {
    service_account = google_service_account.dataform_runtime.email
  }
}
