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

# Output the S3 bucket endpoint
output "s3_endpoint" {
  description = "Endpoint URL for the S3 bucket"
  value       = "https://s3.${var.scw_region}.scw.cloud"
}

# Output SSH connection command
output "ssh_connection_command" {
  description = "Command to connect to the Nextcloud server via SSH"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${scaleway_instance_server.nextcloud.public_ip}"
}

# Output Nextcloud admin credentials (sensitive)
output "nextcloud_admin_credentials" {
  description = "Nextcloud admin credentials"
  value       = "Username: ${var.nextcloud_admin_user}, Password: ${var.nextcloud_admin_password}"
  sensitive   = true
}
