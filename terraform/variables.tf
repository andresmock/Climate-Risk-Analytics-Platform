variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
  default     = "climate-risk-analytics-placeholder"
}

variable "region" {
  description = "Default GCP region for resources."
  type        = string
  default     = "europe-west1"
}
