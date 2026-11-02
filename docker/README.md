# Stack Docker Nextcloud (Postgres local)

Remplace le RDB managé Scaleway (~14,70 €/mois) par un PostgreSQL en conteneur sur l'instance. Fichiers toujours dans le S3 Scaleway.

## Contenu

- `docker-compose.yml` — postgres:16, nextcloud:31-fpm, redis, nginx
- `nginx/nextcloud.conf` — vhost nginx adapté du style fpm officiel
- `.env.example` — variables à copier en `.env`

## Test en local

```bash
cd docker
cp .env.example .env
# Éditer .env : mots de passe, NEXTCLOUD_TRUSTED_DOMAINS="localhost 127.0.0.1", WEB_PORT=8080

docker compose up -d
docker compose logs -f app   # attendre "Initializing finished" / nextcloud installé
```

Puis ouvrir http://localhost:8080 et vérifier :

```bash
# Statut général
docker compose exec app php occ status
docker compose exec app php occ check

# Cron (une fois) puis passer le background jobs sur cron :
docker compose exec -u www-data app php cron.php
docker compose exec -u www-data app php occ config:app:set core backgroundjobs --value="cron"

# Check bas niveau
curl -I http://localhost:8080/status.php
```

Vérifications fonctionnelles :
1. Connexion admin + upload d'un petit fichier (test du datadir local)
2. `docker compose exec db pg_isready -U nextcloud_user -d nextcloud_db`
3. Redémarrage complet (`docker compose down && docker compose up -d`) → données persistées (volumes nommés)

## Branchement S3 (après validation locale, avant la prod)

Dans `config.php` du volume `nextcloud_html` (ou via occ) :

```php
'objectstore' => array(
  'class' => 'OC\\Files\\ObjectStore\\S3',
  'arguments' => array(
    'bucket' => '<S3_BUCKET>',
    'autocreate' => false,
    'hostname' => '<S3_HOSTNAME>',   // ex. s3.fr-par.scw.cloud
    'port' => 443,
    'use_ssl' => true,
    'region' => '<S3_REGION>',
    'legacy_auth' => false,
    'key' => '<S3_KEY>',
    'secret' => '<S3_SECRET>',
  ),
),
```

Identique à la config générée par `install_nextcloud.sh` — la partie S3 est inchangée par rapport à l'install actuelle.

## En prod (plus tard, après terraform)

- TLS : certbot sur l'hôte en mode webroot, ou container compagnon ; le vhost écoute en 80 pour laisser LE renouveler
- Ajouter une politique de dump : `pg_dump` vers S3 dans le cron existant (`backups/layer1`)
- L'app serverless `devoirsfaits` (hors périmètre de ce stack) continuera de pointer vers le RDB ; son recâblage sera fait dans l'étape terraform

## Limites

- Pas de réplication ni backup automatique : le dump S3 devient le seul backup de BDD
- L'app et la base partagent le même hôte (reboot = tout redémarre, géré par `restart`)
