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

# Create a Scaleway instance for Nextcloud
resource "scaleway_instance_server" "nextcloud" {
  name              = "nextcloud-server"
  type              = var.instance_type
  image             = "ubuntu_jammy"  # Ubuntu 22.04
  enable_ipv6       = false
  root_volume {
    size_in_gb = var.root_volume_size
    type       = "bssd"  # SSD
  }

  # SSH key only (no password)
  ssh_key_ids = [scaleway_account_ssh_key.main.id]

  # Security group for SSH, HTTP, HTTPS
  security_group_id = scaleway_instance_security_group.nextcloud.id

  # User data for initial setup (cloud-init)
  user_data = {
    cloud-init = templatefile("${path.module}/modules/nextcloud/scripts/cloud-init.yml", {
      ssh_public_key = var.ssh_public_key
      db_password    = var.db_password
      db_name        = var.db_name
      db_user        = var.db_user
      s3_bucket_name = var.s3_bucket_name
      nextcloud_admin_user = var.nextcloud_admin_user
      nextcloud_admin_password = var.nextcloud_admin_password
      domain_name    = var.domain_name
    })
  }

  tags = ["nextcloud", "terraform"]
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

  # Allow SSH
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 22
    ip       = "0.0.0.0/0"
  }

  # Allow HTTP
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 80
    ip       = "0.0.0.0/0"
  }

  # Allow HTTPS
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 443
    ip       = "0.0.0.0/0"
  }

  # Allow outbound traffic
  outbound_rule {
    action   = "accept"
    protocol = "-1"  # All protocols
    ip       = "0.0.0.0/0"
  }
}

# Scaleway S3 Bucket for Nextcloud files
resource "scaleway_object_bucket" "nextcloud" {
  name = var.s3_bucket_name
  acl  = "private"
  region = var.scw_region
  
  # Enable versioning for backup
  versioning {
    enabled = true
  }
  
  # CORS configuration for Nextcloud
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://${var.domain_name}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# S3 Bucket policy for Nextcloud access
resource "scaleway_object_bucket_policy" "nextcloud" {
  bucket = scaleway_object_bucket.nextcloud.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [scaleway_object_bucket.nextcloud.arn]
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          scaleway_object_bucket.nextcloud.arn,
          "${scaleway_object_bucket.nextcloud.arn}/*"
        ]
      }
    ]
  })
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
    "postgresql.shared_buffers" = "256MB"
  }
  
  # Database initialization
  init_settings = {
    username = var.db_user
    password = var.db_password
    database = var.db_name
  }
  
  # Security group for database
  security_group_id = scaleway_instance_security_group.db.id
  
  tags = ["nextcloud", "postgresql", "terraform"]
}

# Security group for PostgreSQL database
resource "scaleway_instance_security_group" "db" {
  name        = "nextcloud-db-sg"
  description = "Security group for Nextcloud PostgreSQL database"

  # Allow PostgreSQL port from Nextcloud server
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 5432
    ip       = scaleway_instance_server.nextcloud.private_ip
  }

  # Allow outbound traffic
  outbound_rule {
    action   = "accept"
    protocol = "-1"
    ip       = "0.0.0.0/0"
  }
}

# DNS Record for the domain (optional, if using Scaleway DNS)
# Uncomment and configure if you use Scaleway DNS
/*
resource "scaleway_domain_record" "nextcloud" {
  domain = var.domain_name
  type   = "A"
  name   = "@"
  data   = scaleway_instance_server.nextcloud.public_ip
  ttl    = 300
}

resource "scaleway_domain_record" "nextcloud_wildcard" {
  domain = var.domain_name
  type   = "A"
  name   = "*"
  data   = scaleway_instance_server.nextcloud.public_ip
  ttl    = 300
}
*/

# Module for Nextcloud installation (reusable)
module "nextcloud" {
  source = "./modules/nextcloud"
  
  # Instance information
  instance_public_ip = scaleway_instance_server.nextcloud.public_ip
  instance_private_ip = scaleway_instance_server.nextcloud.private_ip
  
  # Database information
  db_host     = scaleway_rdb_instance.nextcloud_db.ip
  db_port     = scaleway_rdb_instance.nextcloud_db.port
  db_name     = var.db_name
  db_user     = var.db_user
  db_password = var.db_password
  
  # S3 Bucket information
  s3_bucket_name = var.s3_bucket_name
  s3_endpoint    = "https://s3.${var.scw_region}.scw.cloud"
  s3_access_key  = var.scw_access_key
  s3_secret_key  = var.scw_secret_key
  s3_region      = var.scw_region
  
  # Nextcloud configuration
  domain_name    = var.domain_name
  admin_user     = var.nextcloud_admin_user
  admin_password = var.nextcloud_admin_password
  
  # SSL configuration
  email = var.ssl_email
  
  # Dependencies
  depends_on = [
    scaleway_instance_server.nextcloud,
    scaleway_rdb_instance.nextcloud_db,
    scaleway_object_bucket.nextcloud
  ]
}
