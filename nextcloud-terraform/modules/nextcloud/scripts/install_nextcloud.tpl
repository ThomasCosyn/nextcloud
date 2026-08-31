#!/bin/bash
# Nextcloud Installation Script for Scaleway
# This script installs Nextcloud manually with:
# - Nginx as web server
# - PostgreSQL as database
# - S3 Scaleway for file storage
# - Let's Encrypt for SSL

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "$$GREEN[INFO]$$NC $1"
}

log_warn() {
    echo -e "$$YELLOW[WARN]$$NC $1"
}

log_error() {
    echo -e "$$RED[ERROR]$$NC $1"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Update system
log_info "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages
log_info "Installing required packages..."
apt-get install -y \
    nginx \
    php8.1-fpm \
    php8.1-gd \
    php8.1-mysql \
    php8.1-pgsql \
    php8.1-curl \
    php8.1-mbstring \
    php8.1-xml \
    php8.1-zip \
    php8.1-intl \
    php8.1-imagick \
    php8.1-ldap \
    php8.1-gmp \
    php8.1-bcmath \
    php8.1-cli \
    php8.1-common \
    postgresql-client \
    certbot \
    python3-certbot-nginx \
    curl \
    wget \
    git \
    unzip \
    jq \
    awscli

# Configure PHP
log_info "Configuring PHP..."
cat > /etc/php/8.1/fpm/pool.d/nextcloud.conf << 'EOL'
[nextcloud]
user = www-data
group = www-data
listen = /run/php/php8.1-fpm-nextcloud.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
php_admin_value[error_log] = /var/log/php-nextcloud.log
php_admin_flag[log_errors] = on
EOL

# Configure PHP.ini settings for Nextcloud
cat >> /etc/php/8.1/fpm/php.ini << 'EOL'

; Nextcloud specific settings
memory_limit = 512M
upload_max_filesize = 512M
post_max_size = 512M
max_execution_time = 3600
max_input_time = 3600
output_buffering = off
session.save_handler = files
opcache.enable=1
opcache.enable_cli=1
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
EOL

# Restart PHP-FPM
systemctl restart php8.1-fpm

# Install and configure Nginx
log_info "Configuring Nginx..."
cat > /etc/nginx/sites-available/nextcloud.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain_name};

    # Security headers
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=()" always;

    # Nextcloud specific headers
    add_header Front-End-Https on;

    # Path to the root of your installation
    root /var/www/nextcloud;
    index index.php index.html index.htm;

    # Prevent direct access to special files
    location ~ /\\.(?!well-known) {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Prevent access to config.php
    location ~ ^/(config\\.php|\\.htaccess) {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Prevent access to data directory
    location ~ ^/data/ {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Rewrite rules
    rewrite ^/caldav(.*)\$ /remote.php/dav/\$1 redirect;
    rewrite ^/carddav(.*)\$ /remote.php/dav/\$1 redirect;
    rewrite ^/webdav(.*)\$ /remote.php/dav/\$1 redirect;

    # Main location block
    location / {
        try_files \$uri \$uri/ =404;
    }

    # PHP handling
    location ~ \\.php(?:\$|/) {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm-nextcloud.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    # Static files
    location ~* \\.(?:css|js|woff2?|svg|gif|map|json)\$ {
        try_files \$uri /index.php\$uri\$is_args\$args;
        add_header Cache-Control "public, max-age=15778463";
        access_log off;
    }

    # Images
    location ~* \\.(?:png|html|ttf|ico|jpg|jpeg|bcmap)\$ {
        try_files \$uri /index.php\$uri\$is_args\$args;
        access_log off;
    }
}
EOF

# Enable the Nextcloud site
ln -sf /etc/nginx/sites-available/nextcloud.conf /etc/nginx/sites-enabled/nextcloud.conf
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

# Restart Nginx
systemctl restart nginx

# Download Nextcloud
log_info "Downloading Nextcloud..."
cd /var/www
wget https://download.nextcloud.com/server/releases/latest.tar.bz2 -O nextcloud.tar.bz2

# Extract Nextcloud
log_info "Extracting Nextcloud..."
tar -xjf nextcloud.tar.bz2
chown -R www-data:www-data /var/www/nextcloud

# Clean up
rm nextcloud.tar.bz2

# Create data directory (we'll use S3, but create local for initial setup)
mkdir -p /var/www/nextcloud/data
chown -R www-data:www-data /var/www/nextcloud/data

# Install and configure S3 client for Nextcloud
log_info "Configuring S3 storage..."

# Create a directory for S3 configuration
mkdir -p /etc/nextcloud

# Create S3 configuration file
cat > /etc/nextcloud/s3-config.json << EOL
{
    "bucket": "${s3_bucket_name}",
    "autocreate": true,
    "key": "${s3_access_key}",
    "secret": "${s3_secret_key}",
    "endpoint": "${s3_endpoint}",
    "region": "${s3_region}",
    "use_ssl": true,
    "use_path_style": false
}
EOL

chown www-data:www-data /etc/nextcloud/s3-config.json
chmod 600 /etc/nextcloud/s3-config.json

# Install PHP S3 SDK
log_info "Installing PHP S3 SDK..."
apt-get install -y php-pear
pear install pear/AWS_SDK_for_PHP

# Install Certbot for Let's Encrypt
log_info "Setting up SSL with Let's Encrypt..."

# Stop Nginx temporarily for Certbot
systemctl stop nginx

# Obtain SSL certificate
certbot certonly --standalone --non-interactive --agree-tos \
    --email ${email} \
    --domains ${domain_name} \
    --preferred-challenges http-01

# Restart Nginx
systemctl start nginx

# Update Nginx configuration to use SSL
cat > /etc/nginx/sites-available/nextcloud.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain_name};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain_name};

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${domain_name}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain_name}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${domain_name}/chain.pem;

    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Security headers
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=()" always;

    # Nextcloud specific headers
    add_header Front-End-Https on;

    # Path to the root of your installation
    root /var/www/nextcloud;
    index index.php index.html index.htm;

    # Prevent direct access to special files
    location ~ /\\.(?!well-known) {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Prevent access to config.php
    location ~ ^/(config\\.php|\\.htaccess) {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Prevent access to data directory
    location ~ ^/data/ {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Rewrite rules
    rewrite ^/caldav(.*)\$ /remote.php/dav/\$1 redirect;
    rewrite ^/carddav(.*)\$ /remote.php/dav/\$1 redirect;
    rewrite ^/webdav(.*)\$ /remote.php/dav/\$1 redirect;

    # Main location block
    location / {
        try_files \$uri \$uri/ =404;
    }

    # PHP handling
    location ~ \\.php(?:\$|/) {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm-nextcloud.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    # Static files
    location ~* \\.(?:css|js|woff2?|svg|gif|map|json)\$ {
        try_files \$uri /index.php\$uri\$is_args\$args;
        add_header Cache-Control "public, max-age=15778463";
        access_log off;
    }

    # Images
    location ~* \\.(?:png|html|ttf|ico|jpg|jpeg|bcmap)\$ {
        try_files \$uri /index.php\$uri\$is_args\$args;
        access_log off;
    }
}
EOF

# Test Nginx configuration
nginx -t

# Restart Nginx
systemctl restart nginx

# Set up Certbot auto-renewal
cat > /etc/cron.d/certbot << EOL
0 */12 * * * root /usr/bin/certbot renew --quiet --post-hook "systemctl reload nginx"
EOL

chmod 644 /etc/cron.d/certbot

# Configure database connection
log_info "Configuring database connection..."

# Create Nextcloud config.php with database settings
cat > /var/www/nextcloud/config/config.php << EOL
<?php
\$CONFIG = array (
  'instanceid' => 'nextcloud-instance',
  'passwordsalt' => '$(openssl rand -base64 32)',
  'secret' => '$(openssl rand -base64 32)',
  'trusted_domains' =>
  array (
    0 => '${domain_name}',
    1 => '${instance_public_ip}',
  ),
  'datadirectory' => '/var/www/nextcloud/data',
  'overwrite.cli.url' => 'https://${domain_name}',
  'dbtype' => 'pgsql',
  'version' => '28.0.0',
  'dbname' => '${db_name}',
  'dbhost' => '${db_host}:${db_port}',
  'dbport' => '${db_port}',
  'dbtableprefix' => 'oc_',
  'dbuser' => '${db_user}',
  'dbpassword' => '${db_password}',
  'installed' => false,
);
EOL

chown www-data:www-data /var/www/nextcloud/config/config.php

# Install Nextcloud via command line
log_info "Installing Nextcloud..."
cd /var/www/nextcloud

# Use occ to install Nextcloud
sudo -u www-data php occ maintenance:install \
    --database "pgsql" \
    --database-host "${db_host}:${db_port}" \
    --database-name "${db_name}" \
    --database-user "${db_user}" \
    --database-pass "${db_password}" \
    --admin-user "${admin_user}" \
    --admin-pass "${admin_password}" \
    --data-dir "/var/www/nextcloud/data"

# Configure S3 as primary storage
log_info "Configuring S3 as primary storage..."

# Install S3 object store app
sudo -u www-data php occ app:install files_external

# Configure S3 object store
sudo -u www-data php occ files_external:create \
    --config bucket=${s3_bucket_name} \
    --config hostname=${s3_endpoint} \
    --config port=443 \
    --config use_ssl=true \
    --config use_path_style=false \
    --config legacy_auth=false \
    --config region=${s3_region} \
    --config key=${s3_access_key} \
    --config secret=${s3_secret_key} \
    Scaleway_S3 \
    amazons3 \
    -1

# Set S3 as default storage
sudo -u www-data php occ files_external:config \
    1 \
    --set-config authtype=accesskey \
    --set-config key=${s3_access_key} \
    --set-config secret=${s3_secret_key}

# Set permissions
log_info "Setting permissions..."
chown -R www-data:www-data /var/www/nextcloud
chmod -R 755 /var/www/nextcloud

# Enable necessary PHP modules
log_info "Enabling PHP modules..."
a2enmod headers rewrite

# Final cleanup
log_info "Cleaning up..."
apt-get autoremove -y
apt-get clean

# Display completion message
log_info ""
log_info "=========================================="
log_info "Nextcloud installation completed!"
log_info "=========================================="
log_info "You can now access Nextcloud at: https://${domain_name}"
log_info "Admin username: ${admin_user}"
log_info "Admin password: ${admin_password}"
log_info ""
log_info "Database information:"
log_info "  Host: ${db_host}:${db_port}"
log_info "  Database: ${db_name}"
log_info "  User: ${db_user}"
log_info ""
log_info "S3 Storage information:"
log_info "  Bucket: ${s3_bucket_name}"
log_info "  Endpoint: ${s3_endpoint}"
log_info ""
log_info "=========================================="
