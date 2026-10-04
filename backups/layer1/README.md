# Layer 1 — daily backup, independent of Terraform

Runs **on the Nextcloud instance** via a systemd timer. Backs up the
PostgreSQL database, the Nextcloud `config.php` and all files from the primary
S3 bucket into a **second S3 bucket, in a separate Scaleway project, created
by hand (outside Terraform)**.

> Why a second bucket in a separate project: the primary bucket and the RDB
> snapshots (Layer 0) live in the same project as the Terraform stack. A
> `terraform destroy` or an accidental project deletion would delete them too.
> The Layer 1 bucket and its IAM keys are unknown to Terraform, so destroying
> the stack leaves the backup intact.

## Files

| File | Purpose |
|------|---------|
| `nextcloud-backup.sh` | Backup script (installed to `/usr/local/sbin/`) |
| `nextcloud-backup.env.example` | Config template (credentials + paths) |
| `rclone.conf.example` | rclone remotes template |
| `nextcloud-backup.service` | systemd unit |
| `nextcloud-backup.timer` | systemd timer (daily 03:00) |

## TODO — one-time setup

Run on the Nextcloud instance as root (Ubuntu).

### 1. Install dependencies

```bash
apt-get update
apt-get install -y rclone postgresql-client
```

### 2. Create the SECOND Scaleway bucket (outside Terraform)

Do this by hand in the Scaleway console / CLI, in a **separate Scaleway
project** (not the one Terraform manages):

1. Create a new Scaleway project (e.g. `nextcloud-backups`).
2. In that project, create an Object Storage bucket, e.g. `nextcloud-backup`.
3. Enable **versioning** on that bucket (recovery from accidental delete/overwrite).
4. (Recommended) Enable an **Object Lock** / lifecycle rule to prevent deletion
   of objects younger than N days.
5. Create a dedicated **IAM API key** in that project with read/write on the
   bucket. Save `access_key_id` + `secret_access_key`.

### 3. Get the source bucket credentials (read-only is enough)

If you don't already have a key with read access to the **primary** bucket
(the one Nextcloud uses, in the Terraform project), create one in that project
(read-only on the bucket).

### 4. Configure rclone

```bash
mkdir -p /root/.config/rclone
cp rclone.conf.example /root/.config/rclone/rclone.conf
chmod 600 /root/.config/rclone/rclone.conf
nano /root/.config/rclone/rclone.conf   # fill in both remotes
```

Verify both remotes work:

```bash
rclone lsd scaleway-src:        # should list the primary bucket
rclone lsd scaleway-backup:     # should list the backup bucket
```

### 5. Configure the backup script

```bash
mkdir -p /etc/nextcloud-backup
cp nextcloud-backup.env.example /etc/nextcloud-backup/nextcloud-backup.env
chmod 600 /etc/nextcloud-backup/nextcloud-backup.env
nano /etc/nextcloud-backup/nextcloud-backup.env
```

Fill in:

- `BACKUP_DB_HOST` / `BACKUP_DB_PORT` / `BACKUP_DB_NAME` / `BACKUP_DB_USER` /
  `BACKUP_DB_PASSWORD` — from `terraform output database_host` and your
  `db_*` Terraform variables.
- `BACKUP_NEXTCLOUD_DIR` — usually `/var/www/nextcloud`.
- `BACKUP_RCLONE_SRC` — `scaleway-src:your-primary-bucket-name`.
- `BACKUP_RCLONE_DST` — `scaleway-backup:nextcloud-backup`.
- `BACKUP_RETENTION_DAYS` — local retention, e.g. `14`.

### 6. Install the script + systemd units

```bash
cp nextcloud-backup.sh /usr/local/sbin/nextcloud-backup.sh
chmod 755 /usr/local/sbin/nextcloud-backup.sh

mkdir -p /var/backups/nextcloud

cp nextcloud-backup.service /etc/systemd/system/
cp nextcloud-backup.timer   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now nextcloud-backup.timer
```

### 7. Test a first run manually

```bash
/usr/local/sbin/nextcloud-backup.sh
journalctl -t nextcloud-backup -e
```

Then check the backup bucket:

```bash
rclone lsd scaleway-backup:nextcloud-backup
rclone lsd scaleway-backup:nextcloud-backup/_nextcloud-db
rclone lsd scaleway-backup:nextcloud-backup/_nextcloud-config
```

### 8. Verify the timer is scheduled

```bash
systemctl list-timers nextcloud-backup.timer
```

## Monitoring

- Logs: `journalctl -t nextcloud-backup -e`
- rclone sync log: `/var/log/nextcloud-backup-rclone.log`
- Last run status: `systemctl status nextcloud-backup.service`

A failed run sets the systemd unit to `failed`, so standard alerting on
`systemctl --failed` (or a cron mail) catches it.

## Restore (quick reference)

1. Recreate the Nextcloud instance + RDB instance via Terraform.
2. Restore the database:
   ```bash
   rclone copy scaleway-backup:nextcloud-backup/_nextcloud-db/db-latest.sql.gz /tmp/
   gunzip < /tmp/db-latest.sql.gz | \
     PGPASSWORD=... pg_restore --host=... --dbname=nextcloud_db --username=nextcloud_user
   ```
   (use `pg_restore` if dump format is custom; adjust to your `pg_dump` flags)
3. Restore `config.php` before any user logs in:
   ```bash
   rclone copy scaleway-backup:nextcloud-backup/_nextcloud-config/config-<date>.tar.gz /tmp/
   tar -xzf /tmp/config-<date>.tar.gz -C /var/www/nextcloud
   chown www-data:www-data /var/www/nextcloud/config/config.php
   ```
4. Point Nextcloud's primary storage config at the restored primary bucket
   (the files themselves are already there, since `rclone sync` copied to the
   backup bucket, not moved). If the primary bucket was destroyed, restore it
   from the backup bucket first:
   ```bash
   rclone sync scaleway-backup:nextcloud-backup scaleway-src:your-primary-bucket-name
   ```

Always test a full restore on a throwaway instance at least once before
relying on this for real.
