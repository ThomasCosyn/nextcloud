# Output the installation script content
output "installation_script" {
  description = "Content of the Nextcloud installation script"
  value       = local_file.nextcloud_install_script.content
  sensitive   = true
}

# Output the installation script path
output "installation_script_path" {
  description = "Path to the Nextcloud installation script"
  value       = local_file.nextcloud_install_script.filename
}
