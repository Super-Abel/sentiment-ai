# infra/monitoring.tf - Prometheus et Grafana provisionnés par Terraform

resource "docker_image" "prometheus" {
  name         = "prom/prometheus:latest"
  keep_locally = true
}

resource "docker_container" "prometheus" {
  name    = "prometheus"
  image   = docker_image.prometheus.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.cicd.name
  }

  ports {
    internal = 9090
    external = 9090
  }

  # Terraform s'exécute dans le conteneur Jenkins (DooD) : un bind-mount avec
  # host_path référencerait un chemin invisible pour le démon Docker de l'hôte.
  # On copie donc le contenu des fichiers directement dans le conteneur.
  upload {
    content    = file("${path.module}/../monitoring/prometheus.yml")
    file       = "/etc/prometheus/prometheus.yml"
  }

  upload {
    content    = file("${path.module}/../monitoring/alerts.yml")
    file       = "/etc/prometheus/alerts.yml"
  }
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:latest"
  keep_locally = true
}

resource "docker_container" "grafana" {
  name    = "grafana"
  image   = docker_image.grafana.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.cicd.name
  }

  ports {
    internal = 3000
    external = 3000
  }

  env = ["GF_SECURITY_ADMIN_PASSWORD=admin"]
}
