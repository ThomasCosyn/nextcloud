terraform {
  required_version = ">= 1.5.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "2.81"
    }
  }
}

# Configure the Scaleway provider
provider "scaleway" {
  zone       = var.scw_zone
  region     = var.scw_region
  access_key = var.scw_access_key
  secret_key = var.scw_secret_key
  project_id = var.scw_project_id
}

# SSH Key resource
resource "scaleway_iam_ssh_key" "main" {
  name       = "nextcloud-ssh-key"
  public_key = var.ssh_public_key
}

# Security Group for Nextcloud server
resource "scaleway_instance_security_group" "nextcloud" {
  name        = "nextcloud-sg"
  description = "Security group for Nextcloud server"

  inbound_default_policy  = "drop"
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

resource "scaleway_instance_ip" "public_ip" {}

# Create a Scaleway instance for Nextcloud
resource "scaleway_instance_server" "nextcloud" {
  name  = "nextcloud-server"
  type  = var.instance_type
  image = "ubuntu_jammy"
  ip_id = scaleway_instance_ip.public_ip.id

  root_volume {
    size_in_gb = var.root_volume_size
  }

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

# Bucket ACL
resource "scaleway_object_bucket_acl" "nextcloud" {
  bucket = scaleway_object_bucket.nextcloud.name
  acl    = "private"
}

# PostgreSQL Database (Scaleway Managed Database)
resource "scaleway_rdb_instance" "nextcloud_db" {
  name              = "nextcloud-db"
  node_type         = var.db_instance_type
  engine            = "PostgreSQL-15"
  is_ha_cluster     = false
  disable_backup    = false
  volume_type       = "sbs_5k"
  volume_size_in_gb = var.db_volume_size
  region            = var.scw_region
  password          = var.db_password
  user_name         = var.db_user

  settings = {
    "max_connections" = "350"
  }

  tags = ["nextcloud", "postgresql", "terraform"]
}

# Security group for PostgreSQL database
resource "scaleway_instance_security_group" "db" {
  name        = "nextcloud-db-sg"
  description = "Security group for Nextcloud PostgreSQL database"

  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = scaleway_rdb_instance.nextcloud_db.load_balancer[0].port
    ip_range = "0.0.0.0/0"
  }
}
