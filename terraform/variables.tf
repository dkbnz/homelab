variable "headscale_version" {
  type    = string
  default = "0.22.3"
}

variable "google_project_id" {
  type = string
}

variable "server_url" {
  type = string
}

variable "backblaze_key" {
  type      = string
  sensitive = true
}

variable "backblaze_key_id" {
  type      = string
  sensitive = true
}
