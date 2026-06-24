# infra/main.tf - Infrastructure SentimentAI via Docker provider

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Windows avec Docker Desktop (named pipe)
provider "docker" {
  host = "npipe:////./pipe/docker_engine"
}

# Réseau Docker partagé Jenkins / SonarQube / SentimentAI
# Ce réseau existe déjà depuis le TP2/TP3 — voir terraform import si conflit
resource "docker_network" "cicd" {
  name = "cicd-network"
}

# Image Docker SentimentAI — image LOCALE buildée par Jenkins
resource "docker_image" "sentiment" {
  name         = "sentiment-ai:${var.image_tag}"
  keep_locally = true
}

# Conteneur staging
resource "docker_container" "sentiment_staging" {
  name    = var.container_name
  image   = docker_image.sentiment.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.cicd.name
  }

  ports {
    internal = 8000
    external = var.app_port
  }

  env = [
    "ENV=staging",
    "LOG_LEVEL=INFO",
  ]

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }
}
