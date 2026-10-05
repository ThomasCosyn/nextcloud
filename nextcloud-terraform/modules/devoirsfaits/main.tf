# Module Devoirs Faits — Serverless Container + Private Network vers la RDB

terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "2.81"
    }
  }
}

# Namespace registry pour l'image de l'app
resource "scaleway_registry_namespace" "devoirsfaits" {
  name        = "devoirsfaits"
  description = "Images pour l'application devoirsfaits"
}

# Namespace serverless
resource "scaleway_container_namespace" "devoirsfaits" {
  name        = "devoirsfaits"
  description = "Assistant devoirsfaits (FastAPI)"
}

# Le container : scale-to-0, port 8080 (uvicorn dans l'image)
resource "scaleway_container" "devoirsfaits" {
  name         = "devoirsfaits"
  namespace_id = scaleway_container_namespace.devoirsfaits.id
  image        = "${scaleway_registry_namespace.devoirsfaits.endpoint}/app:latest"

  port                   = 8080
  min_scale              = 0
  max_scale              = 5
  memory_limit_bytes     = 536870912 # 512 Mo
  cpu_limit              = 280
  timeout                = 60
  privacy                = "public"
  https_connections_only = true
  protocol               = "http1"

  # Réseau privé partagé avec l'instance RDB
  private_network_id = var.devoirsfaits_private_network_id

  environment_variables = {
    MISTRAL_MODEL    = var.devoirsfaits_mistral_model
    MISTRAL_BASE_URL = "https://api.mistral.ai/v1"
    LANGFUSE_HOST    = var.devoirsfaits_langfuse_host
  }

  secret_environment_variables = {
    SECRET_KEY          = var.devoirsfaits_secret_key
    MISTRAL_API_KEY     = var.devoirsfaits_mistral_api_key
    DATABASE_URL        = "postgresql://${var.devoirsfaits_db_user}:${var.devoirsfaits_db_password}@${var.devoirsfaits_db_host}:${var.devoirsfaits_db_port}/devoirsfaits"
    LANGFUSE_PUBLIC_KEY = var.devoirsfaits_langfuse_public_key
    LANGFUSE_SECRET_KEY = var.devoirsfaits_langfuse_secret_key
  }

  lifecycle {
    ignore_changes = [image]
  }
}

output "container_url" {
  value = scaleway_container.devoirsfaits.public_endpoint
}

output "registry_endpoint" {
  value = scaleway_registry_namespace.devoirsfaits.endpoint
}
