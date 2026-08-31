# Scaleway Provider Configuration
variable "scw_region" {
  description = "Scaleway region (e.g., fr-par, nl-ams)"
  type        = string
  default     = "fr-par"
}

variable "scw_zone" {
  description = "Scaleway zone (e.g., fr-par-1, nl-ams-1)"
  type        = string
  default     = "fr-par-1"
}

# Instance Configuration
variable "instance_type" {
  description = "Scaleway instance type for Nextcloud server"
  type        = string
  default     = "Start1-S"  # 2 vCPU, 2 Go RAM
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 50
}

# SSH Configuration
variable "ssh_public_key" {
  description = "Public SSH key for accessing the instance (no password login)"
  type        = string
  sensitive   = true
}

# Domain Configuration
variable "domain_name" {
  description = "Domain name for Nextcloud (e.g., nextcloud.example.com)"
  type        = string
}

# Database Configuration
variable "db_instance_type" {
  description = "Scaleway RDB instance type for PostgreSQL"
  type        = string
  default     = "DB-DEV-S"
}

variable "db_volume_size" {
  description = "Size of the database volume in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Database name for Nextcloud"
  type        = string
  default     = "nextcloud_db"
}

variable "db_user" {
  description = "Database username for Nextcloud"
  type        = string
  default     = "nextcloud_user"
}

variable "db_password" {
  description = "Database password for Nextcloud"
  type        = string
  sensitive   = true
}

# S3 Bucket Configuration
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for Nextcloud files"
  type        = string
}

# Nextcloud Admin Configuration
variable "nextcloud_admin_user" {
  description = "Nextcloud admin username"
  type        = string
  default     = "admin"
}

variable "nextcloud_admin_password" {
  description = "Nextcloud admin password"
  type        = string
  sensitive   = true
}

# SSL Configuration (Let's Encrypt)
variable "ssl_email" {
  description = "Email address for Let's Encrypt certificate"
  type        = string
}

# Scaleway Credentials (sensitive, should be provided via environment variables or secrets)
variable "scw_access_key" {
  description = "Scaleway access key"
  type        = string
  sensitive   = true
  default     = null
}

variable "scw_secret_key" {
  description = "Scaleway secret key"
  type        = string
  sensitive   = true
  default     = null
}
