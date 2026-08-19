terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    # Dataform's own Terraform resources (repository, release/workflow configs) are
    # beta-only, and `google_dataform_repository`'s `git_remote_settings.git_repository_link`
    # (needed to reference the Developer Connect link below) only exists from v7.43.0 — see
    # docs/adr/0008. `google` stays on `~> 6.0`; only the Dataform resources use this provider.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.43.0, < 8.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # Bucket/prefix supplied via `terraform init -backend-config=backend.hcl`
  # (backend.hcl is gitignored — contains the real project's bucket name).
  backend "gcs" {}
}
