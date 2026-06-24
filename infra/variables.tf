# infra/variables.tf - Variables paramétrables de l'infrastructure

variable "image_tag" {
  description = "Tag de l'image Docker à déployer"
  type        = string
  default     = "latest"
}

# Port 8080 réservé à Jenkins — staging sur 8001
variable "app_port" {
  description = "Port exposé en staging"
  type        = number
  default     = 8001
}

variable "container_name" {
  description = "Nom du conteneur staging"
  type        = string
  default     = "sentiment-staging"
}

variable "registry" {
  description = "Registry Docker (ex : ghcr.io/monpseudo)"
  type        = string
  default     = "ghcr.io/super-abel"
}
