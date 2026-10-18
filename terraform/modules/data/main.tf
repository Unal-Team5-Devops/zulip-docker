# Capa de datos: PostgreSQL, memcached, RabbitMQ y Redis.
# - Solo se conectan a la red backend (interna) y no publican puertos.
# - Las contraseñas llegan como archivos de solo lectura en /run/secrets/
#   (bloques upload), nunca como variables de entorno.
# - wait = true: Terraform espera a que cada contenedor esté healthy, así la
#   capa de cómputo no arranca antes que sus dependencias.
locals {
  labels = merge(var.labels, { layer = "data" })
}

resource "docker_image" "postgres" {
  name         = var.images.postgres
  keep_locally = true
}

resource "docker_image" "memcached" {
  name         = var.images.memcached
  keep_locally = true
}

resource "docker_image" "rabbitmq" {
  name         = var.images.rabbitmq
  keep_locally = true
}

resource "docker_image" "redis" {
  name         = var.images.redis
  keep_locally = true
}

resource "docker_container" "postgres" {
  name       = "${var.name_prefix}-postgres"
  image      = docker_image.postgres.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  env = [
    "POSTGRES_DB=zulip",
    "POSTGRES_USER=zulip",
    "POSTGRES_PASSWORD_FILE=/run/secrets/zulip__postgres_password",
  ]

  upload {
    file        = "/run/secrets/zulip__postgres_password"
    content     = var.secrets.postgres_password
    permissions = "0400"
  }

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["database"]
  }

  volumes {
    volume_name    = var.postgres_volume_name
    container_path = "/var/lib/postgresql/data"
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U zulip -d zulip"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 10
    start_period = "20s"
  }
  wait         = true
  wait_timeout = 240

  dynamic "labels" {
    for_each = merge(local.labels, { service = "postgres" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_container" "memcached" {
  name       = "${var.name_prefix}-memcached"
  image      = docker_image.memcached.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  # Configura SASL con el usuario "zulip" y la contraseña del secreto, y arranca
  # memcached con -S (autenticación obligatoria).
  command = [
    "sh",
    "-euc",
    <<-EOT
      umask 077
      echo 'mech_list: plain' > "$SASL_CONF_PATH"
      echo "zulip@$HOSTNAME:$(cat "$MEMCACHED_PASSWORD_FILE")" > "$MEMCACHED_SASL_PWDB"
      echo "zulip@localhost:$(cat "$MEMCACHED_PASSWORD_FILE")" >> "$MEMCACHED_SASL_PWDB"
      exec memcached -S
    EOT
  ]

  env = [
    "SASL_CONF_PATH=/home/memcache/memcached.conf",
    "MEMCACHED_SASL_PWDB=/home/memcache/memcached-sasl-db",
    "MEMCACHED_PASSWORD_FILE=/run/secrets/zulip__memcached_password",
  ]

  # La imagen corre como el usuario memcache (uid 11211).
  upload {
    file        = "/run/secrets/zulip__memcached_password"
    content     = var.secrets.memcached_password
    permissions = "0400"
    owner       = "11211"
    group       = "11211"
  }

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["memcached"]
  }

  # Verificación débil: con SASL activo el protocolo de texto está deshabilitado
  # y no se puede hacer un "ping"; se comprueba que el proceso exista.
  healthcheck {
    test     = ["CMD-SHELL", "pidof memcached"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
  wait         = true
  wait_timeout = 120

  dynamic "labels" {
    for_each = merge(local.labels, { service = "memcached" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_container" "rabbitmq" {
  name       = "${var.name_prefix}-rabbitmq"
  image      = docker_image.rabbitmq.image_id
  hostname   = "rabbitmq"
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  command = [
    "sh",
    "-euc",
    <<-EOT
      export RABBITMQ_DEFAULT_PASS="$(cat "$RABBITMQ_PASSWORD_FILE")"
      exec docker-entrypoint.sh rabbitmq-server
    EOT
  ]

  env = [
    "RABBITMQ_DEFAULT_USER=zulip",
    "RABBITMQ_PASSWORD_FILE=/run/secrets/zulip__rabbitmq_password",
  ]

  upload {
    file        = "/run/secrets/zulip__rabbitmq_password"
    content     = var.secrets.rabbitmq_password
    permissions = "0400"
  }

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["rabbitmq"]
  }

  volumes {
    volume_name    = var.rabbitmq_volume_name
    container_path = "/var/lib/rabbitmq"
  }

  healthcheck {
    test         = ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
    interval     = "15s"
    timeout      = "10s"
    retries      = 10
    start_period = "30s"
  }
  wait         = true
  wait_timeout = 240

  dynamic "labels" {
    for_each = merge(local.labels, { service = "rabbitmq" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_container" "redis" {
  name       = "${var.name_prefix}-redis"
  image      = docker_image.redis.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  # La contraseña va en un archivo de configuración (no en la línea de comandos,
  # donde la vería "ps"). Se relanza el entrypoint con "redis-server" como primer
  # argumento para que baje del usuario root al usuario redis.
  command = [
    "sh",
    "-euc",
    <<-EOT
      umask 077
      printf 'requirepass %s\n' "$(cat "$REDIS_PASSWORD_FILE")" > /tmp/redis.conf
      chown redis /tmp/redis.conf
      exec docker-entrypoint.sh redis-server /tmp/redis.conf
    EOT
  ]

  env = ["REDIS_PASSWORD_FILE=/run/secrets/zulip__redis_password"]

  upload {
    file        = "/run/secrets/zulip__redis_password"
    content     = var.secrets.redis_password
    permissions = "0400"
  }

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["redis"]
  }

  volumes {
    volume_name    = var.redis_volume_name
    container_path = "/data"
  }

  healthcheck {
    test     = ["CMD-SHELL", "redis-cli -a \"$(cat \"$REDIS_PASSWORD_FILE\")\" --no-auth-warning ping | grep -q PONG"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
  wait         = true
  wait_timeout = 120

  dynamic "labels" {
    for_each = merge(local.labels, { service = "redis" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}
