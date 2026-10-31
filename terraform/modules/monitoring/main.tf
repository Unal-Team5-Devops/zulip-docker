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

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "observability", service = "prometheus-data" })
    content {
      label = labels.key
      value = labels.value
    }
  }
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

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "observability", service = "blackbox-exporter" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_container" "postgres_exporter" {
  name       = "zulip-postgres-exporter"
  image      = docker_image.postgres_exporter.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  env = [
    "DATA_SOURCE_URI=database:5432/zulip?sslmode=disable",
    "DATA_SOURCE_USER=zulip",
    "DATA_SOURCE_PASS_FILE=/run/secrets/postgres_password"
  ]

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["postgres-exporter"]
  }

  upload {
    file        = "/run/secrets/postgres_password"
    content     = var.exporter_secrets.postgres_password
    permissions = "0444"
  }

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "observability", service = "postgres-exporter" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_container" "redis_exporter" {
  name       = "zulip-redis-exporter"
  image      = docker_image.redis_exporter.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  command = [
    "--redis.addr=redis://redis:6379",
    "--redis.password-file=/run/secrets/redis_password.json"
  ]

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["redis-exporter"]
  }

  # redis_exporter espera un JSON que mapea la URI de Redis a su contraseña.
  # El secreto se genera en Terraform y no se incorpora al repositorio.
  upload {
    file        = "/run/secrets/redis_password.json"
    content     = jsonencode({ "redis://redis:6379" = var.exporter_secrets.redis_password })
    permissions = "0444"
  }

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "observability", service = "redis-exporter" })
    content {
      label = labels.key
      value = labels.value
    }
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

  depends_on = [
    docker_container.blackbox_exporter,
    docker_container.postgres_exporter,
    docker_container.redis_exporter,
  ]

  networks_advanced {
    name    = var.frontend_network_name
    aliases = ["prometheus"]
  }

  # Prometheus necesita la red backend para recopilar métricas de RabbitMQ y de
  # futuros exportadores de PostgreSQL, Redis y Memcached. No se publica ningún
  # puerto de datos en el host; estos endpoints solo son accesibles dentro de
  # la red backend de Docker.
  networks_advanced {
    name    = var.backend_network_name
    aliases = ["prometheus-backend"]
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

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "observability", service = "prometheus" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}


# Grafana OSS: datasource y dashboard se aprovisionan desde archivos versionados.
resource "docker_image" "postgres_exporter" {
  name         = var.images.postgres_exporter
  keep_locally = true
}

resource "docker_image" "redis_exporter" {
  name         = var.images.redis_exporter
  keep_locally = true
}

resource "docker_image" "grafana" {
  name         = var.images.grafana
  keep_locally = true
}

resource "docker_volume" "grafana_data" {
  name = "zulip-grafana-data"

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "observability", service = "grafana-data" })
    content {
      label = labels.key
      value = labels.value
    }
  }
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

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "observability", service = "grafana" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}
