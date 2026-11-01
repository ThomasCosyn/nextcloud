<?php

/*
 * WARNING
 *
 * This file gets modified by automatic processes and all lines that are not
 * active code (ie. comments) are lost during that process.
 *
 * If you want to document things with comments or use constants add your settings
 * in a '<NAME>.config.php' file which will be included and rendered into this file.
 *
 * Example:
 *   <?php
 *   $CONFIG = [];
 *
 * See also: https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/config_sample_php_parameters.html#multiple-merged-configuration-files
 */
$CONFIG = array (
  'instanceid' => 'nextcloud-instance',
  'passwordsalt' => 'KBbtlknJGm+ypt4xNeaTCcHoBhE4WzSJ',
  'secret' => 'BMQ4tJSawnhWiCqJf7FPQqnOWQmhJIKpMdZsdzfQKZiS79uc',
  'trusted_domains' => 
  array (
    0 => 'nextcloud.goossaertcosyn.fr',
    1 => 'localhost', # TO REMOVE
  ),
  'datadirectory' => '/var/www/html/data',
  # 'overwrite.cli.url' => 'https://nextcloud.goossaertcosyn.fr',
  'dbtype' => 'pgsql',
  'version' => '35.0.0.10',
  'dbname' => 'nextcloud_db',
  'dbhost' => 'db', #'51.15.204.5:23519',
  'dbport' => '5432', #'23519',
  'dbtableprefix' => 'oc_',
  'dbuser' => 'nextcloud_user', #'oc_admin',
  'dbpassword' => 'yBi8D9pQMHPG5cG?', #'iv(3O9RVpQ0td{n.QzpS',
  'installed' => true,
  'maintenance' => false,
  'objectstore' => 
  array (
    'class' => 'OC\\Files\\ObjectStore\\S3',
    'arguments' => 
    array (
      'bucket' => 'nextcloud-files-bucket',
      'autocreate' => false,
      'hostname' => 's3.fr-par.scw.cloud',
      'port' => 443,
      'use_ssl' => true,
      'region' => 'fr-par',
      'key' => 'SCW9SCCDXBY3BYXMWPDN',
      'secret' => '8d5bb407-8431-45a1-9838-456f49d16985',
    ),
  ),
);
