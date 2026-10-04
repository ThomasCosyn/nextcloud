# Nextcloud backups

Strategy in two layers, independent of the Terraform infrastructure.

- **Layer 1 — daily backup, independent of Terraform.** Runs on the Nextcloud
  instance via a systemd timer. Backs up the PostgreSQL database, the
  Nextcloud `config.php` and all files from the primary S3 bucket into a
  **second S3 bucket, in a separate Scaleway project, created by hand (outside
  Terraform)**. Survives `terraform destroy`.
- **Layer 2 — monthly backup, external to Scaleway.** Manual procedure copying
  the same content to an external medium (USB key / hard drive) with
  client-side encryption.

See `layer1/README.md` and `layer2/README.md` for the step-by-step TODO lists.

## Why these two layers

| Layer | Frequency | Content | Destination | Survives |
|-------|-----------|---------|-------------|----------|
| 0 (native Scaleway) | automatic | file versioning + RDB snapshots | same Scaleway project | a single file/DB corruption |
| 1 | daily | DB dump + `config.php` + file sync | 2nd S3 bucket, separate project | `terraform destroy`, bad deploy |
| 2 | monthly | DB dump + all files (encrypted) | USB key / external drive | loss of the whole Scaleway account |

The native Layer 0 already exists (`versioning { enabled = true }` on the
primary bucket and `disable_backup = false` on the RDB instance) but lives in
the same project as the Terraform stack, so it does not protect against a
deployment mistake that destroys the project. Layers 1 and 2 do.
