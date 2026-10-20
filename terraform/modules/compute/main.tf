# Capa de cómputo: solo Zulip (nginx + Django + Tornado + workers).
# Es el único contenedor conectado a las dos redes y el único con puertos
# publicados. No tiene estado propio: /data vive en un volumen del módulo
# persistence, así que se puede reemplazar sin perder datos.
locals {
  labels = merge(var.labels, { layer = "compute", service = "zulip" })

  # El entrypoint de docker-zulip lee /run/secrets/zulip__<nombre> y lo copia
  # a zulip-secrets.conf.
  secret_names = toset([
    "postgres_password",
    "memcached_password",
    "rabbitmq_password",
    "redis_password",
    "secret_key",
    "email_password",
  ])
}

resource "docker_image" "zulip" {
  name         = var.image
  keep_locally = true
}

resource "docker_container" "zulip" {
  name       = "${var.name_prefix}-zulip"
  image      = docker_image.zulip.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  env = [
    "SETTING_REMOTE_POSTGRES_HOST=${var.endpoints.postgres.host}",
    "SETTING_REMOTE_POSTGRES_PORT=${var.endpoints.postgres.port}",
    "SETTING_MEMCACHED_LOCATION=${var.endpoints.memcached.host}:${var.endpoints.memcached.port}",
    "SETTING_RABBITMQ_HOST=${var.endpoints.rabbitmq.host}",
    "SETTING_REDIS_HOST=${var.endpoints.redis.host}",
    "SETTING_EXTERNAL_HOST=${var.external_host}",
    "SETTING_ZULIP_ADMINISTRATOR=${var.admin_email}",
    "CERTIFICATES=${var.certificates}",
  ]

  dynamic "upload" {
    for_each = local.secret_names
    content {
      file        = "/run/secrets/zulip__${upload.value}"
      content     = var.secrets[upload.value]
      permissions = "0400"
    }
  }

  networks_advanced {
    name    = var.frontend_network_name
    aliases = ["zulip"]
  }
  networks_advanced {
    name    = var.backend_network_name
    aliases = ["zulip"]
  }

  # Declarados en orden de puerto interno y con IP concreta: así coinciden con lo
  # que el proveedor lee de Docker y el plan no muestra cambios fantasma.
  ports {
    internal = 80
    external = var.http_port
    ip       = var.bind_address
    protocol = "tcp"
  }
  ports {
    internal = 443
    external = var.https_port
    ip       = var.bind_address
    protocol = "tcp"
  }

  volumes {
    volume_name    = var.zulip_volume_name
    container_path = "/data"
  }

  # Zulip mantiene muchas conexiones abiertas; el límite por defecto no alcanza.
  ulimit {
    name = "nofile"
    soft = 1000000
    hard = 1048576
  }

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}
