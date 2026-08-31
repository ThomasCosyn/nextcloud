# Nextcloud module for manual installation on Scaleway

# Local file for the installation script
resource "local_file" "nextcloud_install_script" {
  filename = "${path.module}/scripts/install_nextcloud.sh"
  content = templatefile("${path.module}/scripts/install_nextcloud.tpl", {
    db_host     = var.db_host
    db_port     = tostring(var.db_port)
    db_name     = var.db_name
    db_user     = var.db_user
    db_password = var.db_password
    s3_bucket_name = var.s3_bucket_name
    s3_endpoint   = var.s3_endpoint
    s3_access_key = var.s3_access_key
    s3_secret_key = var.s3_secret_key
    s3_region     = var.s3_region
    domain_name   = var.domain_name
    admin_user    = var.admin_user
    admin_password = var.admin_password
    email         = var.email
    instance_public_ip = var.instance_public_ip
  })
}
