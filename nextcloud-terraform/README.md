# Nextcloud Terraform Deployment on Scaleway

This repository contains Terraform scripts to deploy Nextcloud **manually** on Scaleway infrastructure with:
- Ubuntu 22.04 instance (Start1-S)
- PostgreSQL managed database
- S3 bucket for file storage
- Nginx with Let's Encrypt SSL
- SSH key-only access

## Prerequisites

- Terraform >= 1.5.0
- Scaleway account with API credentials
- Domain name
- SSH key pair

## Quick Start

### 1. Clone and configure
```bash
git clone <repository-url>
cd nextcloud-terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Set credentials
```bash
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
```

### 3. Deploy infrastructure
```bash
terraform init
terraform plan
terraform apply
```

### 4. Complete installation
```bash
# Get the public IP
terraform output nextcloud_public_ip

# SSH into the server
ssh -i ~/.ssh/your_key ubuntu@<IP>

# Download and run the installation script
wget https://raw.githubusercontent.com/ThomasCosyn/nextcloud/main/nextcloud-terraform/modules/nextcloud/scripts/install_nextcloud.sh
chmod +x install_nextcloud.sh
sudo ./install_nextcloud.sh
```

### 5. Access Nextcloud
Open `https://<your-domain>` in your browser.

## Configuration

### Instance
- Type: Start1-S (2 vCPU, 2GB RAM)
- OS: Ubuntu 22.04
- Storage: 50GB SSD

### Database
- Type: PostgreSQL 15 (DB-DEV-S)
- Storage: 20GB SSD

### Storage
- S3 Bucket (Scaleway)
- Private with CORS enabled

## Terraform Commands

```bash
terraform init    # Initialize
terraform plan    # Review changes
terraform apply   # Apply changes
terraform destroy # Destroy infrastructure
```

## Variables

See `variables.tf` for all configurable parameters.

## Outputs

```bash
terraform output nextcloud_public_ip    # Instance public IP
terraform output nextcloud_url          # Nextcloud URL
terraform output database_host          # Database host
```

## Security

- SSH: Key-only access (no password)
- Database: Not publicly accessible
- S3: Private bucket
- SSL: Let's Encrypt certificates

## License

MIT License
