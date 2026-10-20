# Con docker_host = null el proveedor usa DOCKER_HOST si está definido; de lo
# contrario, se conecta al socket local (unix:///var/run/docker.sock).
# En Windows con Docker Desktop: docker_host = "npipe:////./pipe/docker_engine".
provider "docker" {
  host = var.docker_host
}
