variable "headscale_version" {
  type = string
}

variable "google_project_id" {
  type = string
}

variable "server_url" {
  description = "The URL of the Headscale server."
  type        = string
}

variable "acme_email" {
  description = "The email address to use for ACME registration."
  type        = string
}

variable "base_domain" {
  description = "The base domain for Headscale, used for magic dns."
  type        = string
}

variable "backblaze_key" {
  type      = string
  sensitive = true
}

variable "backblaze_key_id" {
  type      = string
  sensitive = true
}
