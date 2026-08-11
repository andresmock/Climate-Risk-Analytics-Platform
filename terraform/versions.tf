terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Bucket/prefix supplied via `terraform init -backend-config=backend.hcl`
  # (backend.hcl is gitignored — contains the real project's bucket name).
  backend "gcs" {}
}
