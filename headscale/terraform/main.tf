terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  credentials = file("gcp_key.json")

  project = "vocal-lamp-369704"
  region  = "us-central1"
  zone    = "us-central1-c"
}

resource "google_compute_firewall" "ssh" {
  name    = "firewall-external-ssh"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["external-ssh"]
}

resource "google_compute_firewall" "web" {
  name    = "firewall-external-web"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["external-web"]
}

resource "google_compute_address" "headscale" {
  name = "ipv4-address"
}

resource "google_compute_instance" "headscale" {
  name                      = "headscale-instance"
  depends_on                = [google_compute_firewall.ssh, google_compute_firewall.web]
  tags                      = ["external-ssh", "external-web"]
  machine_type              = "e2-micro"
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.headscale.address
    }
  }

}

output "headscale_ip_address" {
  value = google_compute_address.headscale.address
}
