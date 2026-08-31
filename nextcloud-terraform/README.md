# Nextcloud Terraform Deployment on Scaleway

This repository contains Terraform scripts to deploy Nextcloud **manually** on Scaleway infrastructure. The deployment includes:

- **Scaleway Instance** (Ubuntu 22.04) with Nextcloud installed manually
- **PostgreSQL Database** (Scaleway Managed Database)
- **S3 Bucket** for file storage
- **Nginx** web server with Let's Encrypt SSL
- **SSH key-only access** (no password)

## Architecture Overview

```
+-------------------+       +---------------------+       +------------------+
|                   |       |                     |       |                  |
|   Nextcloud       +------>+   PostgreSQL DB      |       |   S3 Bucket      |
|   (Nginx + PHP)   |       |   (Managed)         |       |   (Scaleway)     |
|                   |       |                     |       |                  |
+-------------------+       +---------------------+       +------------------+
        ^                                                                   
        |                                                                   
        +-------------------+                                               
                        |                                               
                        v                                               
                +-------------------+                                       
                |   Internet (HTTPS) |                                       
                +-------------------+                                       
```

## Prerequisites

1. **Terraform** (≥ 1.5.0) installed on your local machine
2. **Scaleway Account** with:
   - API credentials (Access Key and Secret Key)
   - Sufficient credits for resources
3. **Domain Name** pointing to your Scaleway instance (or configure DNS manually)
4. **SSH Key Pair** for instance access

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd nextcloud-terraform
```

### 2. Configure Terraform

#### Copy the example configuration:
```bash
cp terraform.tfvars.example terraform.tfvars
```

#### Edit `terraform.tfvars` with your values:
```hcl
# Scaleway Configuration
scw_region = "fr-par"
scw_zone   = "fr-par-1"

# Instance Configuration
instance_type    = "Start1-S"  # or Start1-M
root_volume_size = 50

# SSH Configuration
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E..."

# Domain Configuration
domain_name = "nextcloud.yourdomain.com"

# Database Configuration
db_instance_type = "DB-DEV-S"
db_volume_size   = 20
db_name          = "nextcloud_db"
db_user          = "nextcloud_user"

# S3 Bucket Configuration
s3_bucket_name = "nextcloud-files-unique-name"

# Nextcloud Admin
nextcloud_admin_user     = "admin"

# SSL Configuration
ssl_email = "admin@yourdomain.com"
```

#### Set Scaleway credentials as environment variables:
```bash
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export TF_VAR_scw_access_key="$SCW_ACCESS_KEY"
export TF_VAR_scw_secret_key="$SCW_SECRET_KEY"
```

> **⚠️ IMPORTANT**: Never commit your actual credentials to version control. Use environment variables or a secrets manager.

### 3. Initialize Terraform

```bash
terraform init
```

This command:
- Downloads the Scaleway provider plugin
- Initializes the backend (local by default)
- Prepares the working directory

### 4. Review the Plan

```bash
terraform plan
```

This will show you:
- All resources that will be created
- The cost estimate
- Any configuration issues

**Review carefully before applying!**

### 5. Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm the changes.

This will:
1. Create a Scaleway instance with Ubuntu 22.04
2. Set up a PostgreSQL managed database
3. Create an S3 bucket for file storage
4. Configure security groups
5. Output connection information

### 6. Complete Nextcloud Installation

After Terraform creates the infrastructure, you need to **manually** complete the Nextcloud installation:

#### SSH into the server:
```bash
ssh -i ~/.ssh/your_private_key ubuntu@<instance-public-ip>
```

#### Run the installation script:
```bash
# The installation script is generated in the module
# Copy it from your local machine or download it

# Make it executable
chmod +x install_nextcloud.sh

# Run as root
sudo ./install_nextcloud.sh
```

The script will:
- Install and configure Nginx
- Install PHP and required extensions
- Download and extract Nextcloud
- Configure PostgreSQL connection
- Set up Let's Encrypt SSL
- Configure S3 storage for Nextcloud files
- Complete the Nextcloud installation

### 7. Access Nextcloud

After the installation script completes:
- Open your browser to: `https://<your-domain-name>`
- Log in with the admin credentials you specified

## Configuration Details

### Instance Configuration

| Resource | Type | Purpose |
|----------|------|---------|
| Scaleway Instance | Start1-S (2 vCPU, 2GB RAM) | Runs Nextcloud, Nginx, PHP |
| Root Volume | 50GB SSD | System and Nextcloud files |
| Security Group | Custom | Allows SSH, HTTP, HTTPS |

### Database Configuration

| Resource | Type | Details |
|----------|------|---------|
| PostgreSQL | DB-DEV-S | Managed database |
| Volume | 20GB SSD | Database storage |
| Version | PostgreSQL 15 | Latest stable version |

### Storage Configuration

| Resource | Type | Details |
|----------|------|---------|
| S3 Bucket | Standard | For Nextcloud file storage |
| Region | fr-par | Same as instance |
| Versioning | Enabled | For backup |

### Network Configuration

| Port | Protocol | Purpose |
|------|----------|---------|
| 22 | TCP | SSH Access |
| 80 | TCP | HTTP (redirects to HTTPS) |
| 443 | TCP | HTTPS (Nextcloud) |

## Manual Steps Required

### 1. DNS Configuration

If you're using an external DNS provider (not Scaleway DNS), you need to:

1. Create an A record pointing to the instance's public IP
2. Optionally, create a wildcard record for subdomains

Example (using Cloudflare, AWS Route 53, etc.):
```
Type: A
Name: @
Value: <instance-public-ip>
TTL: 300
```

### 2. S3 Bucket Configuration in Nextcloud

After Nextcloud is installed:

1. Log in as admin
2. Go to **Settings → Administration → Storage and database**
3. Verify that S3 is configured as the primary storage
4. Test the S3 connection

If you need to reconfigure S3 storage:
```bash
# On the server
sudo -u www-data php /var/www/nextcloud/occ files_external:list
sudo -u www-data php /var/www/nextcloud/occ files_external:config 1 --set-config key=<your-key>
```

### 3. SSL Certificate Renewal

Let's Encrypt certificates expire every 90 days. The installation script sets up automatic renewal:

```bash
# Test renewal
sudo certbot renew --dry-run

# View renewal configuration
cat /etc/cron.d/certbot
```

## Terraform Commands

### Initialize
```bash
terraform init
```

### Plan
```bash
terraform plan
```

### Apply
```bash
terraform apply
```

### Destroy (⚠️ CAUTION: This will delete all resources!)
```bash
terraform destroy
```

### Show Outputs
```bash
terraform output
```

### Refresh State
```bash
terraform refresh
```

## Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `scw_region` | Scaleway region | `fr-par` | No |
| `scw_zone` | Scaleway zone | `fr-par-1` | No |
| `instance_type` | Instance type | `Start1-S` | No |
| `root_volume_size` | Root volume size in GB | `50` | No |
| `ssh_public_key` | SSH public key | - | **Yes** |
| `domain_name` | Domain name for Nextcloud | - | **Yes** |
| `db_instance_type` | Database instance type | `DB-DEV-S` | No |
| `db_volume_size` | Database volume size in GB | `20` | No |
| `db_name` | Database name | `nextcloud_db` | No |
| `db_user` | Database username | `nextcloud_user` | No |
| `db_password` | Database password | - | **Yes** |
| `s3_bucket_name` | S3 bucket name | - | **Yes** |
| `nextcloud_admin_user` | Nextcloud admin username | `admin` | No |
| `nextcloud_admin_password` | Nextcloud admin password | - | **Yes** |
| `ssl_email` | Email for Let's Encrypt | - | **Yes** |

## Outputs Reference

| Output | Description |
|--------|-------------|
| `nextcloud_public_ip` | Public IP of the Nextcloud server |
| `nextcloud_private_ip` | Private IP of the Nextcloud server |
| `nextcloud_url` | URL to access Nextcloud |
| `s3_bucket_name` | Name of the S3 bucket |
| `s3_endpoint` | Endpoint URL for the S3 bucket |
| `database_host` | Host address of the PostgreSQL database |
| `database_port` | Port of the PostgreSQL database |
| `ssh_connection_command` | Command to SSH into the server |

## Security Considerations

### SSH Access
- **Only SSH key authentication** is enabled (password login disabled)
- Security group restricts SSH to all IPs (consider restricting to your IP)

### Database Security
- Database is **not publicly accessible** (only from the Nextcloud instance)
- Strong passwords are recommended

### S3 Bucket Security
- Bucket is **private** by default
- CORS is configured for Nextcloud domain only
- Access keys should be kept secret

### SSL/TLS
- **Let's Encrypt** certificates with automatic renewal
- Strong TLS configuration (TLS 1.2+ only)
- HTTP to HTTPS redirection

## Performance Optimization

### PHP Configuration
The installation script configures PHP with:
- Memory limit: 512MB
- Upload size: 512MB
- Execution time: 3600 seconds
- OPcache enabled

### Nginx Configuration
- Gzip compression enabled
- Caching headers for static files
- Optimized PHP-FPM connection

### Database Optimization
- Connection pool: 100 connections
- Shared buffers: 256MB

## Troubleshooting

### Common Issues

#### 1. SSH Connection Failed
```bash
# Check if the instance is running
terraform output nextcloud_public_ip

# Verify SSH key
chmod 600 ~/.ssh/your_private_key

# Try with verbose output
ssh -v -i ~/.ssh/your_private_key ubuntu@<ip>
```

#### 2. Database Connection Failed
```bash
# Test database connection from the instance
psql -h <db-host> -p <db-port> -U <db-user> -d <db-name>

# Check firewall rules
sudo ufw status
```

#### 3. S3 Connection Failed
```bash
# Test S3 connection
aws s3 --endpoint-url=https://s3.fr-par.scw.cloud ls s3://<bucket-name>

# Check credentials
cat /etc/nextcloud/s3-config.json
```

#### 4. SSL Certificate Failed
```bash
# Check Certbot logs
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Test Nginx configuration
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
```

#### 5. Nextcloud Installation Failed
```bash
# Check Nextcloud logs
tail -f /var/www/nextcloud/data/nextcloud.log

# Check PHP errors
tail -f /var/log/php-nextcloud.log

# Check web server errors
tail -f /var/log/nginx/error.log
```

### Debugging Terraform

#### View Terraform State
```bash
terraform state list
terraform state show <resource>
```

#### Import Existing Resources
```bash
terraform import scaleway_instance_server.nextcloud <server-id>
```

#### Refresh State
```bash
terraform refresh
```

## Scaling Considerations

### Vertical Scaling
To upgrade your instance:
1. Change `instance_type` in `terraform.tfvars`
2. Run `terraform apply`
3. Scaleway will migrate your instance

### Horizontal Scaling
For high availability:
- Consider using multiple instances behind a load balancer
- Use a shared storage solution (S3 is already configured)
- Implement database replication

### Storage Scaling
- S3 buckets scale automatically
- For local storage, increase the root volume size

## Backup Strategy

### 1. Database Backup
```bash
# On the database server
pg_dump -h localhost -U <user> -d <db> > backup.sql
```

### 2. Nextcloud Files Backup
```bash
# If using S3, the bucket itself is the backup
# For additional safety, enable bucket versioning

# If using local storage
sudo -u www-data tar -czf nextcloud-data.tar.gz /var/www/nextcloud/data
```

### 3. Configuration Backup
```bash
# Backup Nextcloud config
sudo cp /var/www/nextcloud/config/config.php /backup/

# Backup Nginx config
sudo cp /etc/nginx/sites-available/nextcloud.conf /backup/

# Backup PHP config
sudo cp /etc/php/8.1/fpm/pool.d/nextcloud.conf /backup/
```

### 4. Terraform State Backup
```bash
# Backup Terraform state
cp terraform.tfstate terraform.tfstate.backup

# Consider using remote backend (S3, etc.)
```

## Cost Estimation

| Resource | Type | Estimated Monthly Cost (EUR) |
|----------|------|-------------------------------|
| Instance | Start1-S | ~5-10 € |
| Instance | Start1-M | ~10-20 € |
| Database | DB-DEV-S | ~10-15 € |
| S3 Bucket | Standard | ~0.01-0.10 € per GB |
| Traffic | Outbound | ~0.01-0.10 € per GB |

**Total estimated cost: ~20-50 €/month** (depending on usage)

## Updates and Maintenance

### Updating Nextcloud
```bash
# On the server
cd /var/www/nextcloud
sudo -u www-data php occ upgrade
sudo -u www-data php occ maintenance:mode --off
```

### Updating System
```bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y
```

### Updating PHP
```bash
sudo apt-get install --only-upgrade php8.1-*
sudo systemctl restart php8.1-fpm
sudo systemctl restart nginx
```

## Module Structure

```
nextcloud-terraform/
├── main.tf                  # Main Terraform configuration
├── variables.tf             # Input variables
├── outputs.tf               # Output values
├── terraform.tfvars.example # Example configuration
├── README.md                # This file
└── modules/
    └── nextcloud/
        ├── main.tf          # Module main configuration
        ├── variables.tf     # Module variables
        └── scripts/
            ├── install_nextcloud.tpl  # Installation script template
            └── cloud-init.yml         # Cloud-init configuration
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review the [Nextcloud documentation](https://docs.nextcloud.com/)
3. Check the [Scaleway documentation](https://www.scaleway.com/en/docs/)
4. Open an issue in this repository

## References

- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [Scaleway Terraform Provider](https://registry.terraform.io/providers/scaleway/scaleway/latest)
- [Let's Encrypt](https://letsencrypt.org/)
- [Nginx Configuration for Nextcloud](https://docs.nextcloud.com/server/latest/admin_manual/installation/nginx.html)
- [PostgreSQL Configuration for Nextcloud](https://docs.nextcloud.com/server/latest/admin_manual/database/postgresql.html)
- [S3 External Storage for Nextcloud](https://docs.nextcloud.com/server/latest/admin_manual/office/object_storage.html)

---

**Note**: This deployment uses manual installation of Nextcloud (not the Scaleway marketplace) as requested. The installation script handles all the necessary steps to set up Nextcloud with Nginx, PostgreSQL, and S3 storage.

*Generated for manual execution as per user requirements.*
