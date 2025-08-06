terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
    b2 = {
      source  = "Backblaze/b2"
      version = "0.8.4"
    }
  }
}

provider "b2" {
  application_key    = var.backblaze_key
  application_key_id = var.backblaze_key_id
}

provider "google" {
  credentials = file("gcp_key.json")

  project = var.google_project_id
  region  = "us-central1"
  zone    = "us-central1-c"
}

module "headscale" {
  source = "./headscale"

  headscale_version = var.headscale_version
  server_url        = var.server_url
  acme_email        = var.acme_email
  base_domain       = var.base_domain
}
