terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.6.0"
    }
  }
}

resource "docker_network" "frontend" {
  name   = "${var.name_prefix}-frontend"
  driver = "bridge"

  labels {
    label = "managed-by"
    value = "terraform"
  }
}

resource "docker_network" "backend" {
  name     = "${var.name_prefix}-backend"
  driver   = "bridge"
  internal = true

  labels {
    label = "managed-by"
    value = "terraform"
  }
}
