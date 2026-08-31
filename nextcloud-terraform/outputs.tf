# Output the public IP of the Nextcloud instance
output "nextcloud_public_ip" {
  description = "Public IP address of the Nextcloud server"
  value       = scaleway_instance_server.nextcloud.public_ip
}

# Output the private IP of the Nextcloud instance
output "nextcloud_private_ip" {
  description = "Private IP address of the Nextcloud server"
  value       = scaleway_instance_server.nextcloud.private_ip
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

# Output the database host
output "database_host" {
  description = "Host address of the PostgreSQL database"
  value       = scaleway_rdb_instance.nextcloud_db.load_balancer[0].ip
}

# Output the database port
output "database_port" {
  description = "Port of the PostgreSQL database"
  value       = scaleway_rdb_instance.nextcloud_db.load_balancer[0].port
}

# Output SSH connection command
output "ssh_connection_command" {
  description = "Command to connect to the Nextcloud server via SSH"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${scaleway_instance_server.nextcloud.public_ip}"
}
