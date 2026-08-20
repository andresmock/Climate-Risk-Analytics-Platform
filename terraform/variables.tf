variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
  default     = "climate-risk-analytics-placeholder"
}

variable "region" {
  description = "Default GCP region for resources."
  type        = string
  default     = "europe-west6"
}

variable "github_actions_wif_member" {
  description = <<-EOT
    Full WIF principal member string granted impersonation rights on ingestion-deploy, e.g.
    "principalSet://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<pool>/attribute.repository/<owner>/<repo>".
    Reuse the exact value already bound to terraform-apply — same pool, same repo restriction,
    different service account. Find it with:
    `gcloud iam service-accounts get-iam-policy terraform-apply@<project>.iam.gserviceaccount.com`
  EOT
  type        = string
}
