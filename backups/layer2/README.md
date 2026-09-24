# Layer 2 — monthly backup to an external medium (USB key / hard drive)

Manual, on-demand procedure to copy a complete encrypted snapshot of your
Nextcloud onto a physical medium you keep offline. This is the only layer that
survives the loss of your whole Scaleway account (billing issue, account
compromise, regional incident).

Your USB key is **200 GB**. The backup is encrypted client-side with rclone
`crypt`, so the key is useless to anyone who finds or steals it without the
crypt password. The key never holds plaintext.

## Files

| File | Purpose |
|------|---------|
| `nextcloud-monthly-usb.sh` | On-demand monthly backup script |
| `rclone-crypt.conf.example` | `usb-crypt` crypt remote template |
| `README.md` | This procedure |

This layer **reuses the Layer 1 config** (`/etc/nextcloud-backup/nextcloud-backup.env`)
for the DB credentials, and the Layer 1 backup bucket as the source of truth
for files. So Layer 1 must be set up first (see `layer1/README.md`).

## What gets copied

```
usb-crypt:_nextcloud/
├── db/        # one compressed pg_dump per month (retention: last KEEP_MONTHS)
├── config/    # one config.php archive per month (retention: last KEEP_MONTHS)
└── files/     # exact mirror of the Layer 1 backup bucket (sync, always up to date)
```

## Capacity planning (200 GB key)

`files/` is a mirror, so it grows with your Nextcloud. DB + config dumps are
tiny in comparison. With a 200 GB key:

- Safe up to **~180 GB** of Nextcloud files (leave headroom for db/config).
- If your photos + documents exceed that, either (a) use a bigger external
  drive, or (b) skip `files/` on the USB key and keep only monthly `db/` +
  `config/` snapshots on the key while relying on Layer 1's cloud bucket for
  files. The script copies `db/` + `config/` first; if `files/` does not fit,
  it fails at the `rclone sync` step without corrupting the previous good
  state.

## TODO — one-time setup

Run on the Nextcloud instance as root. Assumes Layer 1 is already configured
(rclone installed, `/etc/nextcloud-backup/nextcloud-backup.env` present).

### 1. Format the USB key (first time only, destroys existing content)

> ⚠️ This erases everything on the key. Do it only once, on a key you reserve
> for backups.

Plug the key in, identify its device (e.g. `/dev/sdX` — double check with
`lsblk`):

```bash
lsblk
# say the key is /dev/sdX
# wipe it and create one ext4 partition (simple, Linux-friendly, no FAT32 4GB
# file limit, journaled)
sudo parted /dev/sdX --script mklabel gpt mkpart primary ext4 0% 100%
sudo mkfs.ext4 -L nextcloud-usb /dev/sdX1
```

If you prefer the key to be readable on Windows/macOS too, use exFAT instead
of ext4 (`mkfs.exfat`), but ext4 is more robust for unattended writes.

### 2. Set up a stable mount point

```bash
sudo mkdir -p /media/nextcloud-usb
# find the UUID of the new partition
sudo blkid /dev/sdX1
# add to /etc/fstab (replace the UUID):
echo 'UUID=<the-uuid-from-blkid> /media/nextcloud-usb ext4 defaults,nofail,x-systemd.automount 0 2' \
  | sudo tee -a /etc/fstab
sudo mount /media/nextcloud-usb
sudo mkdir -p /media/nextcloud-usb/backup   # this is the `remote` of usb-crypt
```

`nofail,x-systemd.automount` lets the instance boot normally when the key is
not plugged in.

### 3. Configure the rclone `usb-crypt` remote

Append the `usb-crypt` section to the existing rclone config (the same file
Layer 1 uses):

```bash
nano /root/.config/rclone/rclone.conf
# paste the [usb-crypt] block from rclone-crypt.conf.example
```

Choose a **strong crypt password + salt** and obfuscate them (rclone never
stores plaintext):

```bash
rclone obscure            # then type your password, paste the output as `password`
rclone obscure            # then type your salt,     paste the output as `password2`
```

> ⚠️ **Keep the plaintext password + salt somewhere safe and OFF the
> instance** (a password manager). If you lose them, the USB backup is
> unrecoverable. If you store them on the instance and the instance is
> compromised, the backup is compromised too.

Verify the crypt remote works:

```bash
rclone mkdir usb-crypt:_nextcloud
rclone lsd usb-crypt:
# should show _nextcloud (directory names are encrypted, but rclone decrypts
# them when listing through the crypt remote)
```

### 4. Install the monthly script

```bash
cp nextcloud-monthly-usb.sh /usr/local/sbin/nextcloud-monthly-usb.sh
chmod 755 /usr/local/sbin/nextcloud-monthly-usb.sh
```

This is **manual**: you run it yourself once a month. Do not put it on a timer
unless the key is permanently plugged in (not recommended — the point is
offline storage).

## Monthly procedure (do this once a month)

1. Plug in the USB key. Confirm it is mounted:

   ```bash
   lsblk
   mountpoint /media/nextcloud-usb && echo "mounted" || echo "NOT mounted"
   ```

   If not mounted: `sudo mount /media/nextcloud-usb`.

2. Run the backup:

   ```bash
   sudo /usr/local/sbin/nextcloud-monthly-usb.sh
   ```

3. Verify the result:

   ```bash
   rclone lsd usb-crypt:_nextcloud/
   rclone size usb-crypt:_nextcloud/
   ```

4. Sync to disk and unplug safely:

   ```bash
   sync
   sudo umount /media/nextcloud-usb
   # then physically unplug the key and store it somewhere safe, offline
   ```

5. **Optional but recommended:** keep a second USB key and alternate between
   the two each month. If one key dies or is lost, you still have the previous
   month on the other.

## Restore from the USB key

Do this on a machine that has rclone and the **same** `usb-crypt` remote
configured (same password + salt). Plug the key in, mount it at the path the
`usb-crypt` remote points to.

```bash
# 1. restore files to a (new) primary S3 bucket, then point Nextcloud at it
rclone sync usb-crypt:_nextcloud/files/ scaleway-src:your-new-primary-bucket

# 2. restore the database
rclone copy usb-crypt:_nextcloud/db/db-<date>.sql.gz /tmp/
gunzip -c /tmp/db-<date>.sql.gz | \
  PGPASSWORD=... pg_restore --host=... --dbname=nextcloud_db --username=nextcloud_user

# 3. restore config.php before anyone logs in
rclone copy usb-crypt:_nextcloud/config/config-<date>.tar.gz /tmp/
tar -xzf /tmp/config-<date>.tar.gz -C /var/www/nextcloud
chown www-data:www-data /var/www/nextcloud/config/config.php
```

Test a full restore on a throwaway instance at least once before relying on
this for real.

## Security notes

- The key is encrypted, but treat it as sensitive hardware anyway: store it
  offline, physically secure.
- The crypt password + salt are the single point of failure for this layer.
  Store them in a password manager, NOT on the Nextcloud instance and NOT
  next to the key.
- A lost key with a strong password is not a data breach (content is
  encrypted), but it IS a lost backup. Keep at least two media.
