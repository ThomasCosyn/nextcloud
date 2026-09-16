# Output the public IP of the Nextcloud instance
output "nextcloud_public_ip" {
  description = "Public IP address of the Nextcloud server"
  value       = scaleway_instance_server.nextcloud.public_ips
}

# Output the database endpoint (IP) to use for the install script
output "database_host" {
  description = "Database endpoint IP (for the install script's --database-host)",
  value       = scaleway_rdb_instance.nextcloud_db.load_balancer[0].ip
  sensitive   = true
}

# Output the database TLS hostname (for sslmode=verify-full)
output "database_tls_host" {
  description = "Database TLS hostname (rw-<id>.rdb.<region>.scw.cloud) to use with sslmode=verify-full"
  value       = scaleway_rdb_instance.nextcloud_db.load_balancer[0].hostname
}

# Output the database port
output "database_port" {
  description = "Database port"
  value       = scaleway_rdb_instance.nextcloud_db.load_balancer[0].port
  sensitive   = true
}

# Output the private IP of the Nextcloud instance
output "nextcloud_private_ip" {
  description = "Private IP address of the Nextcloud server"
  value       = scaleway_instance_server.nextcloud.private_ips
  sensitive   = true
}

# Output the Nextcloud URL
output "nextcloud_url" {
  description = "URL to access Nextcloud"
  value       = "https://${var.domain_name}"
}

# Output the S3 bucket name
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Nextcloud files"
  value       = scaleway_object_bucket.nextcloud.name
}
