terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.47.0"
    }
    b2 = {
      source  = "Backblaze/b2"
      version = "0.10.0"
    }
  }
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

provider "b2" {
  application_key    = var.backblaze_key
  application_key_id = var.backblaze_key_id
}

resource "b2_bucket" "homelab_backup" {
  bucket_name = "homelab-data-backup"
  bucket_type = "allPrivate"
}

resource "b2_application_key" "homelab_backup_key" {
  key_name     = "homelab-backup-key"
  capabilities = ["listFiles", "readFiles", "writeFiles", "deleteFiles"]
  bucket_id    = b2_bucket.homelab_backup.bucket_id
}
