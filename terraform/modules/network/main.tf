# Dos redes bridge con subred fija:
#   frontend: la única que ve el host; solo Zulip se conecta a ella.
#   backend:  internal = true, sin salida a internet; aquí viven los datos.
resource "docker_network" "frontend" {
  name   = "${var.name_prefix}-frontend"
  driver = "bridge"

  ipam_config {
    subnet  = var.frontend_subnet
    gateway = cidrhost(var.frontend_subnet, 1)
  }

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "network" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}

resource "docker_network" "backend" {
  name     = "${var.name_prefix}-backend"
  driver   = "bridge"
  internal = true

  ipam_config {
    subnet  = var.backend_subnet
    gateway = cidrhost(var.backend_subnet, 1)
  }

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "data" })
    content {
      label = labels.key
      value = labels.value
    }
  }
}
