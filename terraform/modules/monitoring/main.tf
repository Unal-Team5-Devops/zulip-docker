terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.6.0"
    }
  }
}

resource "docker_image" "prometheus" {
  name         = var.images.prometheus
  keep_locally = true
}

resource "docker_image" "blackbox_exporter" {
  name         = var.images.blackbox_exporter
  keep_locally = true
}

resource "docker_volume" "prometheus_data" {
  name = "zulip-prometheus-data"
}

resource "docker_container" "blackbox_exporter" {
  name       = "zulip-blackbox-exporter"
  image      = docker_image.blackbox_exporter.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  command = ["--config.file=/etc/blackbox_exporter/config.yml"]

  networks_advanced {
    name    = var.frontend_network_name
    aliases = ["blackbox-exporter"]
  }

  ports {
    internal = 9115
    external = var.blackbox_port
    ip       = var.bind_address
    protocol = "tcp"
  }

  volumes {
    host_path      = "${var.config_dir}/blackbox.yml"
    container_path = "/etc/blackbox_exporter/config.yml"
    read_only      = true
  }
}

resource "docker_container" "prometheus" {
  name       = "zulip-prometheus"
  image      = docker_image.prometheus.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=35d",
    "--web.enable-lifecycle",
  ]

  depends_on = [docker_container.blackbox_exporter]

  networks_advanced {
    name    = var.frontend_network_name
    aliases = ["prometheus"]
  }

  ports {
    internal = 9090
    external = var.prometheus_port
    ip       = var.bind_address
    protocol = "tcp"
  }

  volumes {
    host_path      = "${var.config_dir}/prometheus.yml"
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }

  volumes {
    host_path      = "${var.config_dir}/slo-rules.yml"
    container_path = "/etc/prometheus/slo-rules.yml"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.prometheus_data.name
    container_path = "/prometheus"
  }
}


# Grafana OSS: datasource y dashboard se aprovisionan desde archivos versionados.
resource "docker_image" "grafana" {
  name         = var.images.grafana
  keep_locally = true
}

resource "docker_volume" "grafana_data" {
  name = "zulip-grafana-data"
}

resource "docker_container" "grafana" {
  name       = "zulip-grafana"
  image      = docker_image.grafana.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  depends_on = [docker_container.prometheus]

  env = [
    "GF_SECURITY_ADMIN_USER=${var.grafana_admin_user}",
    "GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana_admin_password",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_AUTH_ANONYMOUS_ENABLED=false",
    "GF_ANALYTICS_REPORTING_ENABLED=false",
    "GF_ANALYTICS_CHECK_FOR_UPDATES=false",
    "GF_SERVER_ROOT_URL=http://localhost:${var.grafana_port}/",
  ]

  networks_advanced {
    name    = var.frontend_network_name
    aliases = ["grafana"]
  }

  ports {
    internal = 3000
    external = var.grafana_port
    ip       = var.bind_address
    protocol = "tcp"
  }

  volumes {
    volume_name    = docker_volume.grafana_data.name
    container_path = "/var/lib/grafana"
  }

  volumes {
    host_path      = "${var.grafana_config_dir}/provisioning"
    container_path = "/etc/grafana/provisioning"
    read_only      = true
  }

  volumes {
    host_path      = "${var.grafana_config_dir}/dashboards"
    container_path = "/var/lib/grafana/dashboards"
    read_only      = true
  }

  upload {
    file        = "/run/secrets/grafana_admin_password"
    content     = var.grafana_admin_password
    permissions = "0400"
    owner       = "472"
    group       = "472"
  }
}
