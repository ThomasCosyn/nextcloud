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
  default     = "Start1-S"
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 50
}

# SSH Configuration
variable "ssh_public_key" {
  description = "Public SSH key for accessing the instance"
  type        = string
  sensitive   = true
}

# Domain Configuration
variable "domain_name" {
  description = "Domain name for Nextcloud"
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

# SSL Configuration
variable "ssl_email" {
  description = "Email address for Let's Encrypt certificate"
  type        = string
}

# Scaleway Credentials
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

variable "scw_project_id" {
  description = "Scaleway project id"
  type        = string
  sensitive   = true
  default     = null
}


