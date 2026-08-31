# Instance information
variable "instance_public_ip" {
  description = "Public IP address of the instance"
  type        = string
}

variable "instance_private_ip" {
  description = "Private IP address of the instance"
  type        = string
}

# Database information
variable "db_host" {
  description = "Database host address"
  type        = string
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_user" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

# S3 Bucket information
variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "s3_endpoint" {
  description = "S3 endpoint URL"
  type        = string
}

variable "s3_access_key" {
  description = "S3 access key"
  type        = string
  sensitive   = true
}

variable "s3_secret_key" {
  description = "S3 secret key"
  type        = string
  sensitive   = true
}

variable "s3_region" {
  description = "S3 region"
  type        = string
}

# Nextcloud configuration
variable "domain_name" {
  description = "Domain name for Nextcloud"
  type        = string
}

variable "admin_user" {
  description = "Nextcloud admin username"
  type        = string
}

variable "admin_password" {
  description = "Nextcloud admin password"
  type        = string
  sensitive   = true
}

# SSL configuration
variable "email" {
  description = "Email for Let's Encrypt certificate"
  type        = string
}
