terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.6.0"
    }
  }
}

resource "docker_volume" "zulip" {
  name = "${var.name_prefix}-data"

  labels {
    label = "managed-by"
    value = "terraform"
  }
}

resource "docker_volume" "postgres" {
  name = "${var.name_prefix}-postgresql-14"

  labels {
    label = "managed-by"
    value = "terraform"
  }
}

resource "docker_volume" "rabbitmq" {
  name = "${var.name_prefix}-rabbitmq"

  labels {
    label = "managed-by"
    value = "terraform"
  }
}

resource "docker_volume" "redis" {
  name = "${var.name_prefix}-redis"

  labels {
    label = "managed-by"
    value = "terraform"
  }
}
