#!/bin/bash
# Nextcloud Installation Script for Scaleway
# This script must be run manually after Terraform creates the infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "$GREEN[INFO]$NC $1"; }
log_warn() { echo -e "$YELLOW[WARN]$NC $1"; }
log_error() { echo -e "$RED[ERROR]$NC $1"; }

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Get public IP of the instance
PUBLIC_IP=$(curl -s ifconfig.me)
log_info "Detected public IP: $PUBLIC_IP"

# Ask for required variables
read -p "Domain name (e.g., nextcloud.example.com): " DOMAIN_NAME
read -p "Database host (from terraform output): " DB_HOST
read -p "Database port (default 5432): " DB_PORT
DB_PORT=${DB_PORT:-5432}
read -p "Database name (default nextcloud_db): " DB_NAME
DB_NAME=${DB_NAME:-nextcloud_db}
read -p "Database user (default nextcloud_user): " DB_USER
DB_USER=${DB_USER:-nextcloud_user}
read -sp "Database password: " DB_PASSWORD
echo ""
read -p "S3 bucket name: " S3_BUCKET_NAME
read -p "S3 endpoint (e.g., https://s3.fr-par.scw.cloud): " S3_ENDPOINT
read -p "S3 region (e.g., fr-par): " S3_REGION
read -sp "S3 access key: " S3_ACCESS_KEY
echo ""
read -sp "S3 secret key: " S3_SECRET_KEY
echo ""
read -p "Admin username (default admin): " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}
read -sp "Admin password: " ADMIN_PASSWORD
echo ""
read -p "Email for Let's Encrypt: " SSL_EMAIL

log_info "Updating system packages..."
apt-get update -y
apt-get upgrade -y

log_info "Installing required packages..."
apt-get install -y nginx php8.1-fpm php8.1-gd php8.1-mysql php8.1-pgsql \
    php8.1-curl php8.1-mbstring php8.1-xml php8.1-zip php8.1-intl \
    php8.1-imagick php8.1-ldap php8.1-gmp php8.1-bcmath php8.1-cli \
    php8.1-common postgresql-client certbot python3-certbot-nginx \
    curl wget git unzip jq awscli

log_info "Configuring PHP..."
cat > /etc/php/8.1/fpm/pool.d/nextcloud.conf << 'EOF'
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
EOF

cat >> /etc/php/8.1/fpm/php.ini << 'EOF'
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
EOF

systemctl restart php8.1-fpm

log_info "Configuring Nginx..."
cat > /etc/nginx/sites-available/nextcloud.conf << 'NGINXEOF'
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME};

    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=()" always;
    add_header Front-End-Https on;

    root /var/www/nextcloud;
    index index.php index.html index.htm;

    location ~ /\.(?!well-known) {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ ^/(config\.php|\.htaccess) {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ ^/data/ {
        deny all;
        access_log off;
        log_not_found off;
    }

    rewrite ^/caldav(.*)$ /remote.php/dav/$1 redirect;
    rewrite ^/carddav(.*)$ /remote.php/dav/$1 redirect;
    rewrite ^/webdav(.*)$ /remote.php/dav/$1 redirect;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php(?:$|/) {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm-nextcloud.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    location ~* \.(?:css|js|woff2?|svg|gif|map|json)$ {
        try_files $uri /index.php$uri$is_args$args;
        add_header Cache-Control "public, max-age=15778463";
        access_log off;
    }

    location ~* \.(?:png|html|ttf|ico|jpg|jpeg|bcmap)$ {
        try_files $uri /index.php$uri$is_args$args;
        access_log off;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/nextcloud.conf /etc/nginx/sites-enabled/nextcloud.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

log_info "Downloading Nextcloud..."
cd /var/www
wget https://download.nextcloud.com/server/releases/latest.tar.bz2 -O nextcloud.tar.bz2
tar -xjf nextcloud.tar.bz2
chown -R www-data:www-data /var/www/nextcloud
rm nextcloud.tar.bz2

mkdir -p /var/www/nextcloud/data
chown -R www-data:www-data /var/www/nextcloud/data

log_info "Setting up SSL with Let's Encrypt..."
systemctl stop nginx

certbot certonly --standalone --non-interactive --agree-tos \
    --email ${SSL_EMAIL} --domains ${DOMAIN_NAME} --preferred-challenges http-01

systemctl start nginx

cat > /etc/nginx/sites-available/nextcloud.conf << 'NGINXEOF'
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN_NAME};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/chain.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling on;
    ssl_stapling_verify on;

    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=()" always;
    add_header Front-End-Https on;

    root /var/www/nextcloud;
    index index.php index.html index.htm;

    location ~ /\.(?!well-known) {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ ^/(config\.php|\.htaccess) {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ ^/data/ {
        deny all;
        access_log off;
        log_not_found off;
    }

    rewrite ^/caldav(.*)$ /remote.php/dav/$1 redirect;
    rewrite ^/carddav(.*)$ /remote.php/dav/$1 redirect;
    rewrite ^/webdav(.*)$ /remote.php/dav/$1 redirect;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php(?:$|/) {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm-nextcloud.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    location ~* \.(?:css|js|woff2?|svg|gif|map|json)$ {
        try_files $uri /index.php$uri$is_args$args;
        add_header Cache-Control "public, max-age=15778463";
        access_log off;
    }

    location ~* \.(?:png|html|ttf|ico|jpg|jpeg|bcmap)$ {
        try_files $uri /index.php$uri$is_args$args;
        access_log off;
    }
}
NGINXEOF

nginx -t
systemctl restart nginx

cat > /etc/cron.d/certbot << EOF
0 */12 * * * root /usr/bin/certbot renew --quiet --post-hook "systemctl reload nginx"
EOF
chmod 644 /etc/cron.d/certbot

log_info "Configuring database connection..."
cat > /var/www/nextcloud/config/config.php << PHPEOF
<?php
\$CONFIG = array (
  'instanceid' => 'nextcloud-instance',
  'passwordsalt' => '$(openssl rand -base64 32)',
  'secret' => '$(openssl rand -base64 32)',
  'trusted_domains' => array (0 => '${DOMAIN_NAME}'),
  'datadirectory' => '/var/www/nextcloud/data',
  'overwrite.cli.url' => 'https://${DOMAIN_NAME}',
  'dbtype' => 'pgsql',
  'version' => '28.0.0',
  'dbname' => '${DB_NAME}',
  'dbhost' => '${DB_HOST}:${DB_PORT}',
  'dbport' => '${DB_PORT}',
  'dbtableprefix' => 'oc_',
  'dbuser' => '${DB_USER}',
  'dbpassword' => '${DB_PASSWORD}',
  'installed' => false,
);
PHPEOF

chown www-data:www-data /var/www/nextcloud/config/config.php

log_info "Installing Nextcloud..."
cd /var/www/nextcloud

sudo -u www-data php occ maintenance:install \
    --database "pgsql" \
    --database-host "${DB_HOST}:${DB_PORT}" \
    --database-name "${DB_NAME}" \
    --database-user "${DB_USER}" \
    --database-pass "${DB_PASSWORD}" \
    --admin-user "${ADMIN_USER}" \
    --admin-pass "${ADMIN_PASSWORD}" \
    --data-dir "/var/www/nextcloud/data"

log_info "Configuring S3 as primary storage..."
sudo -u www-data php occ app:install files_external

sudo -u www-data php occ files_external:create \
    --config bucket=${S3_BUCKET_NAME} \
    --config hostname=${S3_ENDPOINT} \
    --config port=443 \
    --config use_ssl=true \
    --config use_path_style=false \
    --config legacy_auth=false \
    --config region=${S3_REGION} \
    --config key=${S3_ACCESS_KEY} \
    --config secret=${S3_SECRET_KEY} \
    Scaleway_S3 amazons3 -1

log_info "Setting permissions..."
chown -R www-data:www-data /var/www/nextcloud
chmod -R 755 /var/www/nextcloud

a2enmod headers rewrite

log_info "Cleaning up..."
apt-get autoremove -y
apt-get clean

log_info ""
log_info "=========================================="
log_info "Nextcloud installation completed!"
log_info "=========================================="
log_info "You can now access Nextcloud at: https://${DOMAIN_NAME}"
log_info "Admin username: ${ADMIN_USER}"
log_info ""
log_info "Database: ${DB_HOST}:${DB_PORT}/${DB_NAME}"
log_info "S3 Bucket: ${S3_BUCKET_NAME}"
log_info "=========================================="
