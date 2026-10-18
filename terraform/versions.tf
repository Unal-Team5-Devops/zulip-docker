terraform {
  required_version = ">= 1.6.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.6.0"
    }
  }
}

# El proveedor usa DOCKER_HOST cuando está definido; de lo contrario,
# intenta conectarse al socket/API local de Docker.
provider "docker" {}
