# Runbook : migration de l'install manuelle vers le stack Docker (sur l'instance)

Objectif : remplacer nginx+php-fpm+Nextcloud manuels par le stack docker-compose
(postgres local), sur l'instance Scaleway actuelle. Le RDB managé reste en place
pendant la migration (utilise par devoirsfaits) — il sera supprime plus tard.

Downtime attendu : 30-45 min.

## Vue d'ensemble

1. Pre-flight (sans downtime)
2. Installation de Docker sur l'instance
3. Dernier dump de la base + recuperation data dir
4. Mise en place du stack (sans servir le trafic)
5. Bascule du trafic (downtime commence ici)
6. Tests + validation
7. Decommission de l'ancienne install
8. Nettoyages ulterieurs (terraform, backups, devoirsfaits)

## 1. Pre-flight (sans downtime)

- [ ] Rotation de la cle S3 si pas deja fait (cle exposee dans le PR #10)
- [ ] Verifier l'espace disque : `df -h /` (il faut ~2x la taille du dump + images docker ~2 Go)
- [ ] Verifier le cron certbot actif : `systemctl list-timers | grep certbot`
- [ ] Notifier les utilisateurs (downtime 30-45 min)

## 2. Installation de Docker (sans downtime)

```bash
curl -fsSL https://get.docker.com | sh
docker --version && docker compose version
```

## 3. Donnees (dump a chaud, l'instance continue de tourner)

```bash
# Dump final (dernier etat coherent avant maintenance mode)
pg_dump --no-owner --no-privileges -h 51.15.204.5 -p 23519 -U oc_admin nextcloud_db \
  > /root/migration/nextcloud_db.sql

# Copie du data dir (avatars, cache)
rsync -a /var/www/nextcloud/data/ /root/migration/data/

# Copie des fichiers du stack
cd /root/migration
git clone https://github.com/ThomasCosyn/nextcloud.git repo
```

## 4. Stack en place (toujours sans downtime)

```bash
cd /root/migration/repo/docker
cp .env.example .env
# Editer .env :
#   POSTGRES_PASSWORD=<mdp local choisi>
#   NEXTCLOUD_TRUSTED_DOMAINS=nextcloud.goossaertcosyn.fr
#   WEB_PORT=127.0.0.1:8080        <- accessible seulement via le nginx hote
#   (NEXTCLOUD_ADMIN_* : laisser vide, l'instance existe deja)

docker compose up -d db
docker compose exec -T db psql -U nextcloud_user nextcloud_db < /root/migration/nextcloud_db.sql
```

Preparer le config.php docker (a partir de la copie config.prod.php) :
- 'dbhost' => 'db', 'dbport' => '5432'
- 'dbuser' => 'nextcloud_user', 'dbpassword' => <POSTGRES_PASSWORD>
- 'datadirectory' => '/var/www/html/data'
- 'trusted_domains' => ['nextcloud.goossaertcosyn.fr']
- 'overwrite.cli.url' => 'https://nextcloud.goossaertcosyn.fr'
- section 'objectstore' : INCHANGEE
- secrets (secret, passwordsalt) : INCHANGES

```bash
docker compose up -d app
docker cp config.php $(docker compose ps -q -a app):/var/www/html/config/config.php
docker compose exec app chown www-data:www-data /var/www/html/config/config.php
# injecter le data dir dans le volume nextcloud_data
docker cp /root/migration/data/. $(docker compose ps -q app):/var/www/html/data/
docker compose exec app chown -R www-data:www-data /var/www/html/data
docker compose up -d
docker compose exec -u www-data app php occ status   # installed: true, v35
```

## 5. Bascule trafic (downtime commence)

```bash
# Geler les ecritures sur l'ancienne instance
sudo -u www-data php8.3 /var/www/nextcloud/occ maintenance:mode on

# Dump de rattrapage (ecoule entre le 1er dump et le maintenance mode) :
pg_dump --no-owner --no-privileges -h 51.15.204.5 -p 23519 -U oc_admin nextcloud_db \
  > /root/migration/nextcloud_db_final.sql
docker compose exec -T db psql -U nextcloud_user -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" nextcloud_db
docker compose exec -T db psql -U nextcloud_user nextcloud_db < /root/migration/nextcloud_db_final.sql

# Arreter l'ancien serveur
systemctl stop php8.3-fpm

# nginx hote : remplacer le vhost par un proxy vers le stack docker
# (voir section TLS ci-dessous)

systemctl reload nginx
```

## 6. Tests

- https://nextcloud.goossaertcosyn.fr/status.php -> 200
- Connexion web, app mobile, client desktop (mirall)
- Upload d'un fichier de test -> visible dans le bucket S3
- `docker compose exec -u www-data app php occ status`
- `docker compose exec -u www-data app php occ files:scan --all` (optionnel)

## 7. Decommission ancienne install

```bash
# apres quelques jours de bon fonctionnement :
apt-mark hold php8.3*   # eviter les surprises, ou plutot :
apt purge 'php8.3*' && apt autoremove
rm -rf /var/www/nextcloud   # apres verif que le data dir est bien migre
```

## 8. Ulterieur

- Cron pg_dump vers S3 (remplace les backups RDB) : cf backups/layer1
- Migrer la base devoirsfaits hors RDB puis terraform destroy du RDB (-14,70 EUR/mois)
- Terraform : retirer le bloc RDB, reduire root_volume_size, cloud-init docker

## TLS : architecture retenue

Le nginx de l'HOTE reste le terminateur TLS (certificats letsencrypt deja en place,
renouvellement certbot existant conserve). Il proxifie vers le conteneur docker
web sur 127.0.0.1:8080. Le vhost hote devient :

```nginx
server {
    listen 80;
    server_name nextcloud.goossaertcosyn.fr;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;
    server_name nextcloud.goossaertcosyn.fr;
    ssl_certificate /etc/letsencrypt/live/nextcloud.goossaertcosyn.fr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/nextcloud.goossaertcosyn.fr/privkey.pem;

    client_max_body_size 0;
    client_body_timeout 3600s;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
    }
}
```

Le conteneur web (nginx docker) gere le fastcgi vers app:9000 et les fichiers
statiques. Dans le config.php docker : 'overwriteprotocol' => 'https' pour que
Nextcloud genere des URLs https correctes derriere le proxy.
