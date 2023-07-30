output "backblaze_backup_application_key_id" {
  value = b2_application_key.homelab_backup_key.application_key_id
}

output "backblaze_backup_application_key" {
  value     = b2_application_key.homelab_backup_key.application_key
  sensitive = true
}

output "headscale_ip_address" {
  value = module.headscale.headscale_ip_address
}

resource "local_file" "rclone_config" {
  content  = data.template_file.rclone_config.rendered
  filename = "../ansible/rclone.conf"
}

data "template_file" "rclone_config" {
  template = file("${path.module}/rclone.conf.tpl")
  vars = {
    b2_application_key_id = b2_application_key.homelab_backup_key.application_key_id
    b2_application_key    = b2_application_key.homelab_backup_key.application_key
  }
}
