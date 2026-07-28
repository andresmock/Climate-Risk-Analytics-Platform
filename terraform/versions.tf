terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Local backend for now — no GCP project exists yet to host remote state.
  # Migrates to a GCS backend once the project is provisioned (see docs/adr/0002).
}
