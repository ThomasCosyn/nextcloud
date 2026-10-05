variable "devoirsfaits_secret_key" {
  description = "SECRET_KEY de l'app (signing des sessions)"
  type        = string
  sensitive   = true
}

variable "devoirsfaits_mistral_api_key" {
  description = "Clé API Mistral (texte + photos)"
  type        = string
  sensitive   = true
}

variable "devoirsfaits_mistral_model" {
  description = "Modèle Mistral"
  type        = string
  default     = "mistral-medium-latest"
}

variable "devoirsfaits_langfuse_public_key" {
  description = "Langfuse public key (optionnel)"
  type        = string
  default     = ""
}

variable "devoirsfaits_langfuse_secret_key" {
  description = "Langfuse secret key (optionnel)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "devoirsfaits_langfuse_host" {
  description = "Langfuse host"
  type        = string
  default     = "https://cloud.langfuse.com"
}

variable "devoirsfaits_db_user" {
  description = "Utilisateur PostgreSQL devoirsfaits"
  type        = string
  default     = "devoirsfaits"
}

variable "devoirsfaits_db_password" {
  description = "Mot de passe PostgreSQL devoirsfaits"
  type        = string
  sensitive   = true
}

variable "devoirsfaits_db_port" {
  description = "Port PostgreSQL de l'instance RDB (endpoint privé)"
  type        = number
}

variable "devoirsfaits_db_host" {
  description = "IP privée de l'instance RDB dans le Private Network"
  type        = string
}

variable "devoirsfaits_private_network_id" {
  description = "ID du Private Network partagé avec l'instance RDB"
  type        = string
}
