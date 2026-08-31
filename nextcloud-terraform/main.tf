terraform {
  required_version = ">= 1.5.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.7.0"
    }
  }
}

# Configure the Scaleway provider
provider "scaleway" {
  zone   = var.scw_zone
  region = var.scw_region
}

# SSH Key resource
resource "scaleway_account_ssh_key" "main" {
  name       = "nextcloud-ssh-key"
  public_key = var.ssh_public_key
}

# Security Group for Nextcloud server
resource "scaleway_instance_security_group" "nextcloud" {
  name        = "nextcloud-sg"
  description = "Security group for Nextcloud server"

  inbound_default_policy = "drop"
  outbound_default_policy = "accept"

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 22
    ip_range = "0.0.0.0/0"
  }

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 80
    ip_range = "0.0.0.0/0"
  }

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 443
    ip_range = "0.0.0.0/0"
  }
}

# Create a Scaleway instance for Nextcloud
resource "scaleway_instance_server" "nextcloud" {
  name  = "nextcloud-server"
  type  = var.instance_type
  image = "ubuntu_jammy"
  
  root_volume {
    size_in_gb = var.root_volume_size
  }

  ssh_key_ids = [scaleway_account_ssh_key.main.id]
  security_group_id = scaleway_instance_security_group.nextcloud.id

  user_data = {
    cloud-init = templatefile("${path.module}/modules/nextcloud/scripts/cloud-init.yml", {
      ssh_public_key = var.ssh_public_key
      domain_name    = var.domain_name
    })
  }

  tags = ["nextcloud", "terraform"]
}

# Scaleway S3 Bucket for Nextcloud files
resource "scaleway_object_bucket" "nextcloud" {
  name   = var.s3_bucket_name
  region = var.scw_region
  acl    = "private"

  versioning {
    enabled = true
  }
  
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://${var.domain_name}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# PostgreSQL Database (Scaleway Managed Database)
resource "scaleway_rdb_instance" "nextcloud_db" {
  name           = "nextcloud-db"
  node_type      = var.db_instance_type
  engine         = "PostgreSQL-15"
  is_ha_cluster  = false
  disable_backup = false
  volume_type    = "bssd"
  volume_size_in_gb = var.db_volume_size
  region         = var.scw_region
  
  settings = {
    "postgresql.max_connections" = "100"
    "postgresql.shared_buffers"  = "256MB"
  }
  
  init_settings = {
    username = var.db_user
    password = var.db_password
    database = var.db_name
  }
  
  tags = ["nextcloud", "postgresql", "terraform"]
}

# Security group for PostgreSQL database
resource "scaleway_instance_security_group" "db" {
  name        = "nextcloud-db-sg"
  description = "Security group for Nextcloud PostgreSQL database"

  inbound_default_policy = "drop"
  outbound_default_policy = "accept"

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 5432
    ip_range = "0.0.0.0/0"
  }
}

# Module for Nextcloud installation
module "nextcloud" {
  source = "./modules/nextcloud"

  instance_public_ip  = scaleway_instance_server.nextcloud.public_ip
  instance_private_ip = scaleway_instance_server.nextcloud.private_ip

  db_host     = scaleway_rdb_instance.nextcloud_db.load_balancer[0].ip
  db_port     = scaleway_rdb_instance.nextcloud_db.load_balancer[0].port
  db_name     = var.db_name
  db_user     = var.db_user
  db_password = var.db_password

  s3_bucket_name = var.s3_bucket_name
  s3_endpoint    = "https://s3.${var.scw_region}.scw.cloud"
  s3_access_key  = var.scw_access_key
  s3_secret_key  = var.scw_secret_key
  s3_region      = var.scw_region

  domain_name    = var.domain_name
  admin_user     = var.nextcloud_admin_user
  admin_password = var.nextcloud_admin_password

  email = var.ssl_email

  depends_on = [
    scaleway_instance_server.nextcloud,
    scaleway_rdb_instance.nextcloud_db,
    scaleway_object_bucket.nextcloud
  ]
}
