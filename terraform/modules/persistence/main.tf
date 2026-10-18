# Volúmenes con nombre. Están en un módulo propio para que su ciclo de vida no
# dependa de los contenedores: recrear o reemplazar un contenedor no los toca.
# Memcached es una caché en memoria y no necesita volumen.
locals {
  volumes = {
    zulip    = "${var.name_prefix}-zulip-data"
    postgres = "${var.name_prefix}-postgresql-14"
    rabbitmq = "${var.name_prefix}-rabbitmq"
    redis    = "${var.name_prefix}-redis"
  }
}

resource "docker_volume" "this" {
  for_each = local.volumes

  name = each.value

  dynamic "labels" {
    for_each = merge(var.labels, { layer = "data", service = each.key })
    content {
      label = labels.key
      value = labels.value
    }
  }
}
