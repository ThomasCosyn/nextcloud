# Output the public IP of the Nextcloud instance
output "nextcloud_public_ip" {
  description = "Public IP address of the Nextcloud server"
  value       = scaleway_instance_server.nextcloud.public_ips
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

# Output the devoirsfaits database connection URL (public endpoint, for local CLI/debug)
output "devoirsfaits_database_url" {
  description = "PostgreSQL connection URL for the devoirsfaits database"
  value       = "postgresql://${scaleway_rdb_user.devoirsfaits.name}:${var.devoirsfaits_db_password}@${scaleway_rdb_instance.nextcloud_db.load_balancer[0].ip}:${scaleway_rdb_instance.nextcloud_db.load_balancer[0].port}/${scaleway_rdb_database.devoirsfaits.name}"
  sensitive   = true
}

output "devoirsfaits_registry_endpoint" {
  description = "Container registry endpoint for the devoirsfaits image"
  value       = module.devoirsfaits.registry_endpoint
}

output "devoirsfaits_container_url" {
  description = "Public URL of the devoirsfaits serverless container"
  value       = module.devoirsfaits.container_url
}
