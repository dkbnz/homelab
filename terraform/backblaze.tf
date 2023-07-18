resource "b2_bucket" "homelab_backup" {
    bucket_name = "homelab-data-backup"
    bucket_type = "allPrivate"
}

resource "b2_application_key" "homelab_backup_key" {
    key_name = "homelab-backup-key"
    capabilities = ["listFiles", "readFiles", "writeFiles", "deleteFiles"]
    bucket_id = b2_bucket.homelab_backup.bucket_id
}
