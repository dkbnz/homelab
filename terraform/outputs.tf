output "backblaze_backup_application_key_id" {
  value = b2_application_key.homelab_backup_key.application_key_id
}

output "backblaze_backup_application_key" {
  value     = b2_application_key.homelab_backup_key.application_key
  sensitive = true
}

resource "local_file" "backblaze_key" {
  content  = "{\"key_id\":\"${b2_application_key.homelab_backup_key.application_key_id}\",\"key\":\"${b2_application_key.homelab_backup_key.application_key}\"}\n"
  filename = "backblaze_backup_key.json"
}
