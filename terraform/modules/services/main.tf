terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.6.0"
    }
  }
}

resource "docker_image" "database" {
  name         = "zulip/zulip-postgresql:14"
  keep_locally = true
}

resource "docker_image" "memcached" {
  name         = "memcached:1.6-alpine"
  keep_locally = true
}

resource "docker_image" "rabbitmq" {
  name         = "rabbitmq:4.2"
  keep_locally = true
}

resource "docker_image" "redis" {
  name         = "redis:7-alpine"
  keep_locally = true
}

resource "docker_image" "zulip" {
  name         = var.zulip_image
  keep_locally = true
}

resource "docker_container" "database" {
  name       = "zulip-database"
  image      = docker_image.database.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  env = [
    "POSTGRES_DB=zulip",
    "POSTGRES_USER=zulip",
    "POSTGRES_PASSWORD_FILE=/run/secrets/zulip__postgres_password",
  ]

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["database"]
  }

  volumes {
    volume_name    = var.postgres_volume_name
    container_path = "/var/lib/postgresql/data"
  }
  volumes {
    host_path      = "${var.secrets_dir}/zulip__postgres_password"
    container_path = "/run/secrets/zulip__postgres_password"
    read_only      = true
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
}

resource "docker_container" "memcached" {
  name       = "zulip-memcached"
  image      = docker_image.memcached.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

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

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["memcached"]
  }

  volumes {
    host_path      = "${var.secrets_dir}/zulip__memcached_password"
    container_path = "/run/secrets/zulip__memcached_password"
    read_only      = true
  }

  healthcheck {
    test     = ["CMD-SHELL", "pidof memcached"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
  wait         = true
  wait_timeout = 120
}

resource "docker_container" "rabbitmq" {
  name       = "zulip-rabbitmq"
  image      = docker_image.rabbitmq.image_id
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

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["rabbitmq"]
  }

  volumes {
    volume_name    = var.rabbitmq_volume_name
    container_path = "/var/lib/rabbitmq"
  }
  volumes {
    host_path      = "${var.secrets_dir}/zulip__rabbitmq_password"
    container_path = "/run/secrets/zulip__rabbitmq_password"
    read_only      = true
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
}

resource "docker_container" "redis" {
  name       = "zulip-redis"
  image      = docker_image.redis.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  command = [
    "sh",
    "-euc",
    <<-EOT
      printf 'requirepass %s\n' "$(cat "$REDIS_PASSWORD_FILE")" > /tmp/redis.conf
      exec redis-server /tmp/redis.conf
    EOT
  ]

  env = ["REDIS_PASSWORD_FILE=/run/secrets/zulip__redis_password"]

  networks_advanced {
    name    = var.backend_network_name
    aliases = ["redis"]
  }

  volumes {
    volume_name    = var.redis_volume_name
    container_path = "/data"
  }
  volumes {
    host_path      = "${var.secrets_dir}/zulip__redis_password"
    container_path = "/run/secrets/zulip__redis_password"
    read_only      = true
  }

  healthcheck {
    test     = ["CMD-SHELL", "redis-cli -a \"$(cat $REDIS_PASSWORD_FILE)\" --no-auth-warning ping | grep -q PONG"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
  wait         = true
  wait_timeout = 120
}

resource "docker_container" "zulip" {
  name       = "zulip-app"
  image      = docker_image.zulip.image_id
  restart    = "unless-stopped"
  must_run   = true
  privileged = false

  depends_on = [
    docker_container.database,
    docker_container.memcached,
    docker_container.rabbitmq,
    docker_container.redis,
  ]

  env = [
    "SETTING_REMOTE_POSTGRES_HOST=database",
    "SETTING_MEMCACHED_LOCATION=memcached:11211",
    "SETTING_RABBITMQ_HOST=rabbitmq",
    "SETTING_REDIS_HOST=redis",
    "SETTING_EXTERNAL_HOST=${var.zulip_external_host}",
    "SETTING_ZULIP_ADMINISTRATOR=${var.zulip_admin_email}",
    "CERTIFICATES=self-signed",
  ]

  networks_advanced {
    name    = var.frontend_network_name
    aliases = ["zulip"]
  }
  networks_advanced {
    name    = var.backend_network_name
    aliases = ["zulip"]
  }

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

  volumes {
    host_path      = "${var.secrets_dir}/zulip__postgres_password"
    container_path = "/run/secrets/zulip__postgres_password"
    read_only      = true
  }
  volumes {
    host_path      = "${var.secrets_dir}/zulip__memcached_password"
    container_path = "/run/secrets/zulip__memcached_password"
    read_only      = true
  }
  volumes {
    host_path      = "${var.secrets_dir}/zulip__rabbitmq_password"
    container_path = "/run/secrets/zulip__rabbitmq_password"
    read_only      = true
  }
  volumes {
    host_path      = "${var.secrets_dir}/zulip__redis_password"
    container_path = "/run/secrets/zulip__redis_password"
    read_only      = true
  }
  volumes {
    host_path      = "${var.secrets_dir}/zulip__secret_key"
    container_path = "/run/secrets/zulip__secret_key"
    read_only      = true
  }
  volumes {
    host_path      = "${var.secrets_dir}/zulip__email_password"
    container_path = "/run/secrets/zulip__email_password"
    read_only      = true
  }

  ulimit {
    name = "nofile"
    soft = 1000000
    hard = 1048576
  }
}
