# Devoirs Faits — Serverless Container (scale-to-0)

Déploie l'application [devoirsfaits](https://github.com/ThomasCosyn/devoirsfaits)
(FastAPI) en Serverless Container Scaleway :

- **Container Registry** : namespace `devoirsfaits` (image poussée à la main via `docker push`)
- **Serverless Container** : min_scale 0 (scale-to-0, ~0 € en usage scolaire), port 8080
- **Private Network** partagé entre le container et l'instance RDB `nextcloud_db`
  (le container joint la base par le réseau privé ; l'endpoint public de la RDB
  reste disponible pour le debug depuis votre machine)

## Déploiement

### 1. Variables

Dans `terraform.tfvars` (racine) :

```hcl
devoirsfaits_secret_key      = "..."   # SECRET_KEY de l'app (sessions)
devoirsfaits_mistral_api_key = "..."   # clé API Mistral
# optionnels :
devoirsfaits_mistral_model      = "mistral-medium-latest"
devoirsfaits_langfuse_public_key = ""
devoirsfaits_langfuse_secret_key = ""
devoirsfaits_langfuse_host        = "https://cloud.langfuse.com"
```

### 2. Appliquer

```bash
terraform apply    # crée registry, namespace, container, private network
```

### 3. Construire et pousser l'image

Le module crée le namespace registry ; l'image est poussée depuis le repo
`devoirsfaits` :

```bash
# login (depuis les outputs terraform : devoirsfaits_registry_endpoint)
docker login rg.fr-par.scw.cloud/devoirsfaits -u nologin -p $SCW_SECRET_KEY

cd devoirsfaits
docker build -t rg.fr-par.scw.cloud/devoirsfaits/app:latest -f deploy/Dockerfile .
docker push rg.fr-par.scw.cloud/devoirsfaits/app:latest
```

### 4. Déclencher le premier déploiement

Le provider redéploie automatiquement le container à chaque apply. Au premier
apply l'image n'existe pas encore dans le registry : le container est créé mais
en erreur jusqu'au premier push. Après le premier `docker push`, relancer :

```bash
terraform apply   # ou, dans la console : container → Redeploy
```

### 5. Tester

```bash
curl https://<endpoint-du-container>.functions.fnb.fr-par.scw.cloud/
```

L'URL est dans les outputs (`devoirsfaits_container_url`). Au premier démarrage,
l'app crée le schéma `devoirsfaits` dans la base (schéma déjà initialisé depuis
votre machine, aucune action).

## Réseau

- Le container accède à la base via le **Private Network** (endpoint IPAM de la RDB).
- `DATABASE_URL` est construit automatiquement par le module à partir de
  l'endpoint privé de la RDB :
  `postgresql://devoirsfaits:<password>@<ip_privée>:<port>/devoirsfaits`.
- Le container reçoit une IP privée dans le Private Network (IPAM) et sort sur
  internet via l'endpoint public du container (`privacy = "public"`).
- L'endpoint **public** de la RDB reste inchangé (debug depuis votre machine).

## Domaine custom

Console → Serverless Container → devoirsfaits → Domains → ajouter
`assistant.votredomaine.fr` (CNAME vers l'hostname fourni, HTTPS automatique).
