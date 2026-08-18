provider "google" {
  project = var.project_id
  region  = var.region
}

# See terraform/versions.tf for why this is needed alongside `google`.
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
